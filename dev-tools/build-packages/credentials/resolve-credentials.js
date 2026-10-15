/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * The dashboard's credential resolver. Run as root, by bin/resolve-credentials, on the Node
 * runtime the package bundles:
 *
 *   --install    fresh postinst / %post. Stores what it can, issues the TLS pair, imports the
 *                peers' CAs and prints where to log in. Always exits 0.
 *   --upgrade    postinst / %post on upgrade. Keystore and passwords only. Always exits 0.
 *   --prestart   the unit's ExecStartPre=+. Checks the files, resolves again, re-imports the
 *                peers' CAs, and exits 1 naming every problem that would keep the dashboard
 *                from working.
 *   --clear      image builds. Removes what the resolver stored, issued and minted.
 *
 * Per-package model: the dashboard owns /etc/wazuh-dashboard (its CA in ca/, what it publishes in
 * export/) and only reads its peers' export/ directories. /etc/wazuh is never touched.
 *
 * Every file read as root must be a regular file in a regular directory, both owned by root and
 * neither group- nor world-writable. Anything else is reported as UNSAFE and is never used,
 * repaired or followed.
 */

const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const SERVICE = 'wazuh-dashboard';
const PID_FILE = '/run/wazuh-dashboard/wazuh-dashboard.pid';
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const TEN_YEARS_MS = 3650 * ONE_DAY_MS;

const CA_MARKER = '.wazuh-dashboard-bootstrap-ca';
const CERT = 'dashboard.pem';
const KEY = 'dashboard-key.pem';

// What each peer publishes and what the dashboard takes from it. Each connection is verified
// with its own peer's CA, in certs/<name>-ca.pem.
const PEERS = [
  {
    name: 'indexer',
    exportDir: '/etc/wazuh-indexer/export',
    key: 'WAZUH_INDEXER_KIBANASERVER_PASSWORD',
    alias: 'INDEXER_PASSWORD',
    account: "the indexer's kibanaserver account",
    entry: 'opensearch.password',
    username: { entry: 'opensearch.username', value: 'kibanaserver' },
    // Without the indexer's password and CA the dashboard cannot work at all.
    required: true,
    caMissing: 'no CA to verify the indexer with',
  },
  {
    name: 'manager',
    exportDir: '/etc/wazuh-manager/export',
    key: 'WAZUH_MANAGER_WUI_PASSWORD',
    alias: 'API_PASSWORD',
    account: "the manager's wazuh-internal-client account",
    entry: 'wazuh_core.hosts.default.password',
    // Without a default host there is nothing to authenticate.
    neededIf: 'wazuh_core.hosts.default',
    // Without the manager's password or CA the dashboard still serves the indexer data; only
    // the Server API is refused, until a start finds them.
    required: false,
    caMissing:
      'the Server API connection is refused until it is present; ' +
      'once wazuh-manager is installed, the next start imports it',
  },
];

const peerCa = (peer) => `${peer.name}-ca.pem`;
const peerMarker = (peer) => `.${peer.name}-ca.imported`;

const AI_KEY_ENTRY = 'wazuh_ai_assistant.encryptionKey';
// The keystore entries the resolver set, one per line, so --clear removes those and no other.
const ENTRIES_RECORD = '.resolved-keystore-entries';

const log = (msg) => process.stdout.write(`resolve-credentials: ${msg}\n`);
const err = (msg) => process.stderr.write(`resolve-credentials: ${msg}\n`);

function createContext({
  home,
  configDir,
  rootUid = 0,
  rootGid = 0,
  peers = PEERS,
  env = process.env,
} = {}) {
  return {
    home,
    configDir,
    rootUid,
    rootGid,
    peers,
    env,
    verbose: env.WAZUH_DASHBOARD_VERBOSE === '1',
    gid: null,
    problems: [],
    reported: new Set(),
    keys: null,
    runKeystore: (args, input) => runKeystore(home, configDir, args, input),
  };
}

const detail = (ctx, msg) => ctx.verbose && log(msg);

function unsafe(ctx, file, reason) {
  const line = `UNSAFE ${file}: ${reason}`;
  if (!ctx.reported.has(line)) {
    ctx.reported.add(line);
    ctx.problems.push(line);
    err(line);
  }
}

// ---------------------------------------------------------------------------------------------
// Trust rules
// ---------------------------------------------------------------------------------------------

function trustReason(ctx, stat, kind) {
  if (stat.isSymbolicLink()) return 'it is a symbolic link';
  if (kind === 'dir' ? !stat.isDirectory() : !stat.isFile()) {
    return kind === 'dir' ? 'it is not a directory' : 'it is not a regular file';
  }
  if (stat.uid !== ctx.rootUid) return 'it is not owned by root';
  if (stat.mode & 0o022) return 'it is group- or world-writable';
  return null;
}

// A secret others can read is still trusted (nobody else can change it), but it is reported.
function warnReadable(ctx, file, stat, kind) {
  if (kind !== 'secret' || !(stat.mode & 0o044)) return;
  const line = `warning: ${file} is group- or world-readable; it holds passwords: chmod 600 ${file}`;
  if (!ctx.reported.has(line)) {
    ctx.reported.add(line);
    err(line);
  }
}

function lstatOrNull(file) {
  try {
    return fs.lstatSync(file);
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
}

// true: trusted, false: absent, null: unsafe (reported).
function trustedDir(ctx, dir) {
  const stat = lstatOrNull(dir);
  if (!stat) return false;
  const reason = trustReason(ctx, stat, 'dir');
  if (reason) {
    unsafe(ctx, dir, reason);
    return null;
  }
  return true;
}

// The file's contents, undefined when it (or its directory) is absent, null when unsafe.
// Opened without following a link and checked through the descriptor, so a name swapped
// between the check and the read is not read.
function readTrusted(ctx, file, kind = 'file') {
  const dirState = trustedDir(ctx, path.dirname(file));
  if (dirState !== true) return dirState === false ? undefined : null;
  let fd;
  try {
    fd = fs.openSync(
      file,
      fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK
    );
  } catch (e) {
    if (e.code === 'ENOENT') return undefined;
    if (e.code === 'ELOOP') {
      unsafe(ctx, file, 'it is a symbolic link');
      return null;
    }
    unsafe(ctx, file, e.code || e.message);
    return null;
  }
  try {
    const stat = fs.fstatSync(fd);
    const reason = trustReason(ctx, stat, kind);
    if (reason) {
      unsafe(ctx, file, reason);
      return null;
    }
    warnReadable(ctx, file, stat, kind);
    return fs.readFileSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}

function restorecon(file) {
  spawnSync('restorecon', [file], { stdio: 'ignore' });
}

const O_DIR = fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW;

// A descriptor on a real directory owned by root and writable by nobody else, or a thrown error.
function openTrustedDir(ctx, dir) {
  const fd = fs.openSync(dir, O_DIR);
  const reason = trustReason(ctx, fs.fstatSync(fd), 'dir');
  if (reason) {
    fs.closeSync(fd);
    unsafe(ctx, dir, reason);
    throw new Error(`cannot write in ${dir}`);
  }
  return fd;
}

// A name inside the directory behind `fd`, resolved through the descriptor (what renameat would
// do), so the directory cannot be swapped for another between the check and the write.
// ponytail: Node has no *at() calls; /proc/self/fd gives the same on Linux, the plain path is
// only for running the tests on other systems.
function at(fd, dir, name) {
  return fs.existsSync('/proc/self/fd') ? `/proc/self/fd/${fd}/${name}` : path.join(dir, name);
}

// Creates the directory when absent; an existing one must already be trusted. The owner and the
// mode of a new directory are set through a descriptor, never by path.
function ensureDir(ctx, dir, mode, gid) {
  const state = trustedDir(ctx, dir);
  if (state !== false) return state === true;
  fs.mkdirSync(dir, { mode: 0o700 });
  const fd = fs.openSync(dir, O_DIR);
  try {
    fs.fchownSync(fd, ctx.rootUid, gid);
    fs.fchmodSync(fd, mode);
  } finally {
    fs.closeSync(fd);
  }
  restorecon(dir);
  return trustedDir(ctx, dir) === true;
}

// Temporary file and rename, through a descriptor on a trusted directory.
function writeTrusted(ctx, file, data, { mode = 0o640, gid = serviceGid(ctx) } = {}) {
  const dir = path.dirname(file);
  const name = path.basename(file);
  const dfd = openTrustedDir(ctx, dir);
  try {
    const tmp = at(dfd, dir, `.${name}.${crypto.randomBytes(6).toString('hex')}`);
    const fd = fs.openSync(
      tmp,
      fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW,
      0o600
    );
    try {
      fs.writeFileSync(fd, data);
      fs.fchownSync(fd, ctx.rootUid, gid);
      fs.fchmodSync(fd, mode);
      fs.fsyncSync(fd);
    } catch (e) {
      fs.closeSync(fd);
      fs.rmSync(tmp, { force: true });
      throw e;
    }
    fs.closeSync(fd);
    fs.renameSync(tmp, at(dfd, dir, name));
  } finally {
    fs.closeSync(dfd);
  }
  restorecon(file);
}

function serviceGid(ctx) {
  if (ctx.gid === null) {
    const out = spawnSync('getent', ['group', SERVICE], { encoding: 'utf8' });
    const gid = Number((out.stdout || '').split(':')[2]);
    if (out.status === 0 && Number.isInteger(gid)) {
      ctx.gid = gid;
    } else {
      err(`cannot find the ${SERVICE} group; files are left readable by root only`);
      ctx.gid = ctx.rootGid;
    }
  }
  return ctx.gid;
}

// ---------------------------------------------------------------------------------------------
// Values: the process environment, then local.env, then the publisher's export/credentials.env
// ---------------------------------------------------------------------------------------------

function parseEnv(text) {
  const values = {};
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\r$/, '');
    const eq = line.indexOf('=');
    if (/^\s*(#|$)/.test(line) || eq < 1) continue;
    let value = line.slice(eq + 1);
    // No accepted password contains a quote, so a quoted value is unquoted.
    const quoted = value.match(/^(["'])(.*)\1$/);
    if (quoted) value = quoted[2];
    values[line.slice(0, eq).trim()] = value;
  }
  return values;
}

// local.env holds passwords: readable by others is reported, not refused.
function readEnvFile(ctx, file) {
  const kind = path.basename(file) === 'local.env' ? 'secret' : 'file';
  const data = readTrusted(ctx, file, kind);
  return data ? parseEnv(data.toString('utf8')) : {};
}

// An empty value is no hit, unless `allowEmpty`: then it is returned for the caller to refuse.
function lookup(ctx, key, alias, publisherDir, { allowEmpty = false } = {}) {
  const hit = (value) => value !== undefined && (value !== '' || allowEmpty);
  for (const name of [key, alias].filter(Boolean)) {
    if (hit(ctx.env[name])) return { value: ctx.env[name], source: `the environment (${name})` };
  }
  const sources = [path.join(ctx.configDir, 'local.env')];
  if (publisherDir) sources.push(path.join(publisherDir, 'credentials.env'));
  for (const file of sources) {
    const value = readEnvFile(ctx, file)[key];
    if (hit(value)) return { value, source: file };
  }
  return null;
}

// `keystore add` trims the value and stores it JSON.parse'd when it parses (src/cli_keystore/
// add.js), so only a value that survives both is stored as the text supplied.
function storesVerbatim(value) {
  const trimmed = value.trim();
  let parsed;
  try {
    parsed = JSON.parse(trimmed);
  } catch (e) {
    parsed = undefined;
  }
  return (parsed ?? trimmed) === value;
}

// ---------------------------------------------------------------------------------------------
// opensearch_dashboards.yml
// ---------------------------------------------------------------------------------------------

function loadYml(ctx) {
  const data = readTrusted(ctx, path.join(ctx.configDir, 'opensearch_dashboards.yml'));
  if (!data) return {};
  try {
    return require('js-yaml').load(data.toString('utf8')) || {};
  } catch (e) {
    // A broken yml is the dashboard's to report when it starts.
    return {};
  }
}

// Flat (`a.b: x`), nested and mixed keys all mean the same thing to the dashboard.
function ymlGet(node, parts) {
  if (parts.length === 0) return node;
  if (node === null || typeof node !== 'object') return undefined;
  for (let i = parts.length; i > 0; i--) {
    const head = parts.slice(0, i).join('.');
    if (Object.prototype.hasOwnProperty.call(node, head)) {
      const found = ymlGet(node[head], parts.slice(i));
      if (found !== undefined) return found;
    }
  }
  return undefined;
}

function ymlHas(yml, key) {
  const value = ymlGet(yml, key.split('.'));
  return (
    (typeof value === 'string' && value !== '') ||
    (value !== null && typeof value === 'object' && Object.keys(value).length > 0)
  );
}

// ---------------------------------------------------------------------------------------------
// Keystore: the bundled CLI, as root with --allow-root, an empty environment, from /
// ---------------------------------------------------------------------------------------------

function runKeystore(home, configDir, args, input = '') {
  const out = spawnSync(
    path.join(home, 'node', 'bin', 'node'),
    [path.join(home, 'src', 'cli_keystore', 'dist'), ...args, '--allow-root'],
    { cwd: '/', env: { OSD_PATH_CONF: configDir, NODE_ENV: 'production' }, input, encoding: 'utf8' }
  );
  return { ok: out.status === 0, stdout: out.stdout || '' };
}

function keystorePath(ctx) {
  return path.join(ctx.configDir, 'opensearch_dashboards.keystore');
}

// The CLI writes the keystore 0600; the service reads it through its group.
function secureKeystore(ctx) {
  const fd = fs.openSync(keystorePath(ctx), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  try {
    fs.fchownSync(fd, ctx.rootUid, serviceGid(ctx));
    fs.fchmodSync(fd, 0o640);
  } finally {
    fs.closeSync(fd);
  }
}

function loadKeys(ctx) {
  const { ok, stdout } = ctx.runKeystore(['list']);
  ctx.keys = ok ? new Set(stdout.split('\n').filter(Boolean)) : null;
  return ctx.keys;
}

function ensureKeystore(ctx) {
  const stat = lstatOrNull(keystorePath(ctx));
  if (stat) {
    const reason = trustReason(ctx, stat, 'file');
    if (reason) {
      unsafe(ctx, keystorePath(ctx), reason);
      return false;
    }
  } else {
    ctx.runKeystore(['create']);
    if (!lstatOrNull(keystorePath(ctx))) return false;
    log(`created the keystore in ${keystorePath(ctx)}`);
  }
  secureKeystore(ctx);
  return loadKeys(ctx) !== null;
}

function recordPath(ctx) {
  return path.join(ctx.configDir, ENTRIES_RECORD);
}

// null when the record is unsafe (reported).
function readRecord(ctx) {
  const data = readTrusted(ctx, recordPath(ctx));
  if (data === null) return null;
  return new Set(data ? data.toString('utf8').split('\n').filter(Boolean) : []);
}

function keystoreAdd(ctx, entry, value) {
  const { ok } = ctx.runKeystore(['add', entry, '--stdin'], value);
  secureKeystore(ctx);
  if (ok) {
    ctx.keys.add(entry);
    const record = readRecord(ctx);
    if (record && !record.has(entry)) {
      record.add(entry);
      writeTrusted(ctx, recordPath(ctx), [...record].join('\n') + '\n', {
        mode: 0o600,
        gid: ctx.rootGid,
      });
    }
  }
  return ok;
}

// ---------------------------------------------------------------------------------------------
// Passwords
// ---------------------------------------------------------------------------------------------

// 'stored', 'missing' or 'invalid'.
function resolvePassword(ctx, yml, peer) {
  if (ctx.keys.has(peer.entry)) {
    detail(ctx, `${peer.entry} is already in the keystore`);
    return 'stored';
  }
  if (ymlHas(yml, peer.entry)) {
    detail(ctx, `${peer.entry} is set in opensearch_dashboards.yml`);
    return 'stored';
  }
  if (peer.neededIf && !ymlHas(yml, peer.neededIf)) {
    detail(ctx, `no ${peer.neededIf} in opensearch_dashboards.yml; ${peer.key} is not needed`);
    return 'stored';
  }
  const found = lookup(ctx, peer.key, peer.alias, peer.exportDir);
  if (!found) return 'missing';
  if (!storesVerbatim(found.value)) {
    err(`${peer.key} from ${found.source} cannot be stored in the keystore as text`);
    return 'invalid';
  }
  const { username } = peer;
  if (
    username &&
    !ctx.keys.has(username.entry) &&
    !ymlHas(yml, username.entry) &&
    !keystoreAdd(ctx, username.entry, username.value)
  ) {
    err(`could not write ${username.entry} to the keystore`);
    return 'missing';
  }
  if (!keystoreAdd(ctx, peer.entry, found.value)) {
    err(`could not write ${peer.entry} to the keystore`);
    return 'missing';
  }
  log(`stored ${peer.entry} in the keystore from ${found.source}`);
  return 'stored';
}

// The AI assistant encrypts the provider keys it stores with it, so an existing key is never
// replaced. The assistant is optional: failing here is a warning only.
function resolveAiKey(ctx, yml) {
  if (ctx.keys.has(AI_KEY_ENTRY) || ymlHas(yml, AI_KEY_ENTRY)) return;
  if (keystoreAdd(ctx, AI_KEY_ENTRY, crypto.randomBytes(32).toString('base64'))) {
    log(`generated ${AI_KEY_ENTRY}`);
  } else {
    err(`warning: could not generate ${AI_KEY_ENTRY}; configure it to enable the AI assistant`);
  }
}

// ---------------------------------------------------------------------------------------------
// Certificates
// ---------------------------------------------------------------------------------------------

const subject = (cn) => [
  { name: 'countryName', value: 'US' },
  { name: 'localityName', value: 'California' },
  { name: 'organizationName', value: 'Wazuh' },
  { shortName: 'OU', value: 'Wazuh' },
  { name: 'commonName', value: cn },
];

// The short host name; a host named by its address keeps the whole address.
function shortHostname() {
  const host = os.hostname();
  return net.isIP(host) ? host : host.split('.')[0];
}

function fqdn(host) {
  const out = spawnSync('getent', ['hosts', host], { encoding: 'utf8' });
  const name = (out.stdout || '').trim().split(/\s+/)[1];
  return out.status === 0 && name ? name : null;
}

// Interfaces that carry a default route, from the kernel's routing tables.
function defaultRouteInterfaces() {
  const names = new Set();
  const read = (file) => {
    try {
      return fs.readFileSync(file, 'utf8').split('\n');
    } catch (e) {
      return [];
    }
  };
  for (const line of read('/proc/net/route').slice(1)) {
    const [iface, destination] = line.trim().split(/\s+/);
    if (destination === '00000000') names.add(iface);
  }
  for (const line of read('/proc/net/ipv6_route')) {
    const fields = line.trim().split(/\s+/);
    if (fields[0] === '0'.repeat(32) && fields[1] === '00' && fields[9] !== 'lo') {
      names.add(fields[9]);
    }
  }
  return names;
}

function isGlobalAddress(address) {
  const a = address.toLowerCase();
  return !(a.startsWith('127.') || a.startsWith('169.254.') || a === '::1' || /^fe[89ab]/.test(a));
}

function discoverAddresses() {
  const interfaces = os.networkInterfaces();
  const addresses = [];
  for (const name of defaultRouteInterfaces()) {
    for (const { address, internal } of interfaces[name] || []) {
      if (!internal && isGlobalAddress(address)) addresses.push(address);
    }
  }
  return addresses;
}

const DNS_NAME = /^(?!-)[A-Za-z0-9*-]+(?<!-)(\.(?!-)[A-Za-z0-9-]+(?<!-))*$/;

// `DNS:x,IP:y,z` into [{ type: 'DNS'|'IP', value }], deduplicated. Throws on a bad entry.
function parseSans(list) {
  const sans = [];
  const seen = new Set();
  for (const item of list
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)) {
    const typed = item.match(/^(DNS|IP):(.*)$/i);
    const value = typed ? typed[2].trim() : item;
    const untyped = net.isIP(value) ? 'IP' : 'DNS';
    const type = typed ? typed[1].toUpperCase() : untyped;
    const valid = type === 'IP' ? net.isIP(value) : value.length <= 253 && DNS_NAME.test(value);
    if (!valid) throw new Error(`invalid SAN entry: ${item}`);
    const id = `${type}:${value.toLowerCase()}`;
    if (!seen.has(id)) {
      seen.add(id);
      sans.push({ type, value });
    }
  }
  return sans;
}

// Throws on an invalid or empty WAZUH_DASHBOARD_CERT_SANS.
function leafSans(ctx, host) {
  const override = lookup(ctx, 'WAZUH_DASHBOARD_CERT_SANS', null, null, { allowEmpty: true });
  let list;
  if (override) {
    detail(ctx, `SANs set by WAZUH_DASHBOARD_CERT_SANS from ${override.source}`);
    if (parseSans(override.value).length === 0) {
      throw new Error(`WAZUH_DASHBOARD_CERT_SANS from ${override.source} is empty`);
    }
    list = [override.value];
  } else {
    const full = fqdn(host);
    // Untyped, so a host named by its address becomes an IP SAN.
    list = [host];
    if (full && full !== host && DNS_NAME.test(full)) list.push(`DNS:${full}`);
    list.push(...discoverAddresses().map((a) => `IP:${a}`));
  }
  list.push('DNS:localhost', 'IP:127.0.0.1', 'IP:::1');
  return parseSans(list.join(','));
}

function newKeyPair(forge) {
  const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const key = forge.pki.privateKeyFromPem(pem);
  return { pem, key, publicKey: forge.pki.setRsaPublicKey(key.n, key.e) };
}

function newCertificate(forge, publicKey) {
  const cert = forge.pki.createCertificate();
  cert.publicKey = publicKey;
  // A positive 128-bit serial.
  cert.serialNumber = '01' + crypto.randomBytes(15).toString('hex');
  // Backdated a day, so a peer whose clock is a little behind still accepts it.
  cert.validity.notBefore = new Date(Date.now() - ONE_DAY_MS);
  cert.validity.notAfter = new Date(Date.now() + TEN_YEARS_MS);
  return cert;
}

function mintCa(forge, host) {
  const { pem, key, publicKey } = newKeyPair(forge);
  const cert = newCertificate(forge, publicKey);
  cert.setSubject(subject(`wazuh-dashboard-${host}`));
  cert.setIssuer(subject(`wazuh-dashboard-${host}`));
  cert.setExtensions([
    { name: 'basicConstraints', cA: true, critical: true },
    { name: 'keyUsage', keyCertSign: true, cRLSign: true, critical: true },
    { name: 'subjectKeyIdentifier' },
  ]);
  cert.sign(key, forge.md.sha256.create());
  return { certPem: forge.pki.certificateToPem(cert), keyPem: pem };
}

function issueLeaf(forge, caCertPem, caKeyPem, host, sans) {
  const caCert = forge.pki.certificateFromPem(caCertPem);
  const caKey = forge.pki.privateKeyFromPem(caKeyPem);
  const { pem, publicKey } = newKeyPair(forge);
  const cert = newCertificate(forge, publicKey);
  cert.setSubject(subject(host));
  cert.setIssuer(caCert.subject.attributes);
  cert.setExtensions([
    { name: 'basicConstraints', cA: false, critical: true },
    { name: 'keyUsage', digitalSignature: true, keyEncipherment: true, critical: true },
    { name: 'extKeyUsage', serverAuth: true, clientAuth: true },
    { name: 'subjectKeyIdentifier' },
    {
      name: 'authorityKeyIdentifier',
      keyIdentifier: caCert.generateSubjectKeyIdentifier().getBytes(),
    },
    {
      name: 'subjectAltName',
      altNames: sans.map(({ type, value }) =>
        type === 'IP' ? { type: 7, ip: value } : { type: 2, value }
      ),
    },
  ]);
  cert.sign(caKey, forge.md.sha256.create());
  return { certPem: forge.pki.certificateToPem(cert), keyPem: pem };
}

// A usable CA: a CA certificate, in date, whose key matches.
function validCa(certPem, keyPem) {
  try {
    const cert = new crypto.X509Certificate(certPem);
    const now = Date.now();
    return (
      cert.ca &&
      Date.parse(cert.validFrom) <= now &&
      now <= Date.parse(cert.validTo) &&
      (keyPem === undefined || cert.checkPrivateKey(crypto.createPrivateKey(keyPem)))
    );
  } catch (e) {
    return false;
  }
}

// The CA in ca/: minted when absent, a staged pair (no marker) validated and used as is.
function ensureCa(ctx, forge) {
  const caDir = path.join(ctx.configDir, 'ca');
  if (!ensureDir(ctx, caDir, 0o700, ctx.rootGid)) return null;
  const certFile = path.join(caDir, 'root-ca.pem');
  const keyFile = path.join(caDir, 'root-ca.key');
  const certPem = readTrusted(ctx, certFile);
  const keyPem = readTrusted(ctx, keyFile);
  if (certPem === null || keyPem === null) return null;
  if (certPem && keyPem) {
    if (!validCa(certPem, keyPem)) {
      err(`the CA in ${caDir} is not a valid, current CA with its private key`);
      return null;
    }
    if (crypto.createPrivateKey(keyPem).asymmetricKeyType !== 'rsa') {
      err(`the CA in ${caDir} does not have an RSA key; only RSA can sign the certificate`);
      return null;
    }
    detail(ctx, `using the CA in ${caDir}`);
    return { certPem: certPem.toString(), keyPem: keyPem.toString() };
  }
  if (certPem || keyPem) {
    err(`only one of root-ca.pem and root-ca.key exists in ${caDir}; refusing to complete it`);
    return null;
  }
  const ca = mintCa(forge, shortHostname());
  // The marker first: a CA without it would pass for the operator's and never be cleared.
  writeTrusted(ctx, path.join(caDir, CA_MARKER), '', { mode: 0o600, gid: ctx.rootGid });
  writeTrusted(ctx, keyFile, ca.keyPem, { mode: 0o400, gid: ctx.rootGid });
  writeTrusted(ctx, certFile, ca.certPem, { mode: 0o644, gid: ctx.rootGid });
  log(`created the dashboard CA in ${caDir}`);
  return ca;
}

function certsDir(ctx) {
  return path.join(ctx.configDir, 'certs');
}

function resolveCertificate(ctx) {
  const dir = certsDir(ctx);
  if (!ensureDir(ctx, dir, 0o750, serviceGid(ctx))) return false;
  const hasCert = Boolean(lstatOrNull(path.join(dir, CERT)));
  const hasKey = Boolean(lstatOrNull(path.join(dir, KEY)));
  if (hasCert && hasKey) {
    detail(ctx, `${dir} already holds a certificate pair; it is kept as it is`);
    return true;
  }
  if (hasCert || hasKey) {
    err(`only one of ${CERT} and ${KEY} exists in ${dir}; refusing to complete it`);
    return false;
  }
  const forge = require('node-forge');
  const ca = ensureCa(ctx, forge);
  if (!ca) return false;
  const host = shortHostname();
  let sans;
  try {
    sans = leafSans(ctx, host);
  } catch (e) {
    err(e.message);
    return false;
  }
  detail(ctx, `issuing ${CERT} for ${host}; SANs ${sans.map((s) => `${s.type}:${s.value}`)}`);
  const leaf = issueLeaf(forge, ca.certPem, ca.keyPem, host, sans);
  // The key first: an interrupted run leaves half a pair, which the next run refuses.
  writeTrusted(ctx, path.join(dir, KEY), leaf.keyPem);
  // The leaf followed by the CA, so a client can build the chain.
  writeTrusted(ctx, path.join(dir, CERT), leaf.certPem + ca.certPem);
  log(`issued ${path.join(dir, CERT)}`);

  const exportDir = path.join(ctx.configDir, 'export');
  if (ensureDir(ctx, exportDir, 0o700, ctx.rootGid)) {
    writeTrusted(ctx, path.join(exportDir, 'ca.pem'), ca.certPem, {
      mode: 0o644,
      gid: ctx.rootGid,
    });
    detail(ctx, `published ${path.join(exportDir, 'ca.pem')}`);
  }
  return true;
}

// One CA file per peer, certs/<peer>-ca.pem:
//   * present without its import marker: staged by the operator, used as is, never replaced;
//   * absent, or present with the marker: copied from the peer's export/ca.pem whenever it
//     differs, so a reinstalled peer is picked up at the next start;
//   * either way it must be a CA certificate.
// Returns 'ok', 'missing', 'invalid' or 'unsafe'.
function resolvePeerCa(ctx, peer) {
  const dir = certsDir(ctx);
  const dest = path.join(dir, peerCa(peer));
  const staged = Boolean(lstatOrNull(dest)) && !lstatOrNull(path.join(dir, peerMarker(peer)));
  let current = readTrusted(ctx, dest);
  if (current === null) return 'unsafe';

  if (staged) {
    detail(ctx, `${dest} has no ${peerMarker(peer)}; it is the operator's and is used as is`);
  } else {
    const source = path.join(peer.exportDir, 'ca.pem');
    const published = readTrusted(ctx, source);
    if (published && !validCa(published)) {
      err(`${source} is not a valid, current CA certificate; it is not imported`);
    } else if (published && !(current && current.equals(published))) {
      // The marker first: an import without it would pass for the operator's and never be
      // refreshed again.
      writeTrusted(ctx, path.join(dir, peerMarker(peer)), '');
      writeTrusted(ctx, dest, published);
      log(`imported ${dest} from ${source}`);
      current = published;
    }
  }
  if (!current) return 'missing';
  return validCa(current) ? 'ok' : 'invalid';
}

// The files root relies on, checked at every start whether or not anything is left to resolve.
function checkFiles(ctx) {
  const groups = {
    '.': ['local.env', ENTRIES_RECORD],
    certs: [CERT, KEY, ...ctx.peers.flatMap((p) => [peerCa(p), peerMarker(p)])],
    ca: ['root-ca.pem', 'root-ca.key', CA_MARKER],
    export: ['ca.pem'],
  };
  for (const [sub, names] of Object.entries(groups)) {
    const dir = path.join(ctx.configDir, sub);
    if (trustedDir(ctx, dir) !== true) continue;
    for (const name of names) {
      const file = path.join(dir, name);
      const stat = lstatOrNull(file);
      if (!stat) continue;
      const kind = name === 'local.env' ? 'secret' : 'file';
      const reason = trustReason(ctx, stat, kind);
      if (reason) unsafe(ctx, file, reason);
      else warnReadable(ctx, file, stat, kind);
    }
  }
}

// The first global address in the certificate's SANs, else its first DNS name, else the host.
function dashboardAddress(ctx) {
  try {
    const cert = new crypto.X509Certificate(fs.readFileSync(path.join(certsDir(ctx), CERT)));
    const sans = (cert.subjectAltName || '').split(/,\s*/);
    const ip = sans
      .filter((s) => s.startsWith('IP Address:'))
      .map((s) => s.slice('IP Address:'.length))
      .find(isGlobalAddress);
    if (ip) return net.isIPv6(ip) ? `[${ip}]` : ip;
    const dns = sans.find((s) => s.startsWith('DNS:') && s !== 'DNS:localhost');
    if (dns) return dns.slice(4);
  } catch (e) {
    // Fall back to the host name.
  }
  return os.hostname();
}

function printFirstLogin(ctx) {
  const indexer = ctx.peers.find((p) => p.name === 'indexer');
  process.stdout.write(
    `\nWazuh dashboard: https://${dashboardAddress(ctx)}\n` +
      'Log in as admin, with WAZUH_INDEXER_ADMIN_PASSWORD from ' +
      `${path.join(indexer.exportDir, 'credentials.env')} on the indexer host.\n` +
      'Start the dashboard and enable it at boot: systemctl enable --now wazuh-dashboard\n'
  );
}

// ---------------------------------------------------------------------------------------------
// --clear
// ---------------------------------------------------------------------------------------------

function dashboardIsRunning() {
  const unit = spawnSync('systemctl', ['is-active', '--quiet', `${SERVICE}.service`]);
  if (unit.status === 0) return true;
  try {
    const pid = Number(fs.readFileSync(PID_FILE, 'utf8').trim());
    // 0 or 1 would signal the process group or init, not the dashboard.
    if (!Number.isInteger(pid) || pid <= 1) return false;
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return false;
  }
}

function removeFrom(ctx, dir, names) {
  const state = trustedDir(ctx, dir);
  if (state === null) return false;
  if (state === false) return true;
  for (const name of names) {
    const file = path.join(dir, name);
    if (lstatOrNull(file)) {
      fs.rmSync(file, { force: true });
      log(`removed ${file}`);
    }
  }
  if (fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
  return true;
}

function clear(ctx) {
  if (dashboardIsRunning()) {
    err('refusing to clear credentials while the dashboard is running');
    err('        stop it first: systemctl stop wazuh-dashboard');
    return 1;
  }
  if (trustedDir(ctx, ctx.configDir) !== true) return 1;

  // Only a pair issued from ca/, and only imported peer CAs: a pair from another CA, or a staged
  // peer CA (no marker), is the operator's.
  const issued = issuedFromOwnCa(ctx);
  const certs = issued ? [CERT, KEY] : [];
  if (!issued && lstatOrNull(path.join(certsDir(ctx), CERT))) {
    log(`kept ${path.join(certsDir(ctx), CERT)} and its key: they were not issued from ca/`);
  }
  for (const peer of ctx.peers) {
    if (lstatOrNull(path.join(certsDir(ctx), peerMarker(peer)))) {
      certs.push(peerCa(peer), peerMarker(peer));
    }
  }
  let ok = removeFrom(ctx, certsDir(ctx), certs);

  const caDir = path.join(ctx.configDir, 'ca');
  if (lstatOrNull(path.join(caDir, CA_MARKER))) {
    ok = removeFrom(ctx, caDir, ['root-ca.pem', 'root-ca.key', 'root-ca.srl', CA_MARKER]) && ok;
  } else if (lstatOrNull(caDir)) {
    log(`kept the CA in ${caDir}: this dashboard did not mint it`);
  }
  ok = removeFrom(ctx, path.join(ctx.configDir, 'export'), ['ca.pem']) && ok;

  const record = readRecord(ctx);
  if (record === null) return 1;
  if (lstatOrNull(keystorePath(ctx)) && record.size) {
    if (!ensureKeystore(ctx)) return 1;
    const entries = [...record].filter((e) => ctx.keys.has(e));
    for (const entry of entries) ctx.runKeystore(['remove', entry]);
    secureKeystore(ctx);
    // Read back rather than trusted from exit codes: a keystore that still holds them is the
    // failure this path exists to prevent.
    const keys = loadKeys(ctx);
    const left = keys ? entries.filter((e) => keys.has(e)) : entries;
    if (left.length) {
      err(`could not remove from the keystore: ${left.join(' ')}`);
      return 1;
    }
    if (entries.length) log(`removed ${entries.join(' ')} from the keystore`);
  }
  fs.rmSync(recordPath(ctx), { force: true });
  if (!ok) return 1;
  // A start never issues certificates (only --install does); it resolves everything else.
  log(
    issued
      ? 'cleared; run resolve-credentials --install to issue a new certificate pair, then start'
      : 'cleared; the next start resolves the passwords and the peer CAs again'
  );
  return 0;
}

// Whether certs/dashboard.pem was issued from the CA in ca/.
function issuedFromOwnCa(ctx) {
  try {
    const ca = readTrusted(ctx, path.join(ctx.configDir, 'ca', 'root-ca.pem'));
    const leaf = readTrusted(ctx, path.join(certsDir(ctx), CERT));
    if (!ca || !leaf) return false;
    return new crypto.X509Certificate(leaf).verify(new crypto.X509Certificate(ca).publicKey);
  } catch (e) {
    return false;
  }
}

// ---------------------------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------------------------

function resolve(ctx, mode) {
  if (trustedDir(ctx, ctx.configDir) !== true) {
    if (!ctx.problems.length) ctx.problems.push(`MISSING ${ctx.configDir}`);
    return ctx.problems;
  }
  checkFiles(ctx);
  const yml = loadYml(ctx);
  const passwords = {};
  if (ensureKeystore(ctx)) {
    for (const peer of ctx.peers) passwords[peer.key] = resolvePassword(ctx, yml, peer);
    if (mode !== 'upgrade') resolveAiKey(ctx, yml);
  } else {
    ctx.problems.push(`MISSING keystore: ${keystorePath(ctx)} could not be created or read`);
  }

  if (mode === 'install' && !resolveCertificate(ctx)) {
    err(`the dashboard has no TLS certificates and this install could not issue them`);
    err(`        provision ${CERT} and ${KEY} into ${certsDir(ctx)}`);
  }
  const cas = {};
  if (mode !== 'upgrade' && ensureDir(ctx, certsDir(ctx), 0o750, serviceGid(ctx))) {
    for (const peer of ctx.peers) cas[peer.name] = resolvePeerCa(ctx, peer);
  }
  if (mode === 'install') printFirstLogin(ctx);

  for (const peer of ctx.peers) {
    if (passwords[peer.key] === 'invalid') {
      ctx.problems.push(
        `INVALID ${peer.key}: the keystore would not store the supplied value as text`,
        '        (it must not be JSON nor have surrounding whitespace)'
      );
    } else if (passwords[peer.key] === 'missing') {
      const hint =
        `        set it in ${path.join(ctx.configDir, 'local.env')}, ` +
        `or install wazuh-${peer.name} on this host first`;
      if (peer.required) {
        ctx.problems.push(`MISSING ${peer.key} (${peer.account})`, hint);
      } else if (mode === 'prestart') {
        err(`warning: MISSING ${peer.key} (${peer.account}): ${peer.caMissing}`);
        err(hint);
      }
    }
  }
  const dir = certsDir(ctx);
  for (const peer of ctx.peers) {
    const file = path.join(dir, peerCa(peer));
    // Not resolved this run (--upgrade): judged by presence only.
    const state = cas[peer.name] || (lstatOrNull(file) ? 'ok' : 'missing');
    if (state === 'invalid') {
      ctx.problems.push(`INVALID ${file}: it is not a valid, current CA certificate`);
    } else if (state === 'missing' && peer.required) {
      ctx.problems.push(`MISSING ${file}: ${peer.caMissing}`);
    } else if (state === 'missing' && mode === 'prestart') {
      err(`warning: MISSING ${file}: ${peer.caMissing}`);
    }
  }
  for (const name of [CERT, KEY]) {
    if (!lstatOrNull(path.join(dir, name))) {
      ctx.problems.push(
        `MISSING ${path.join(dir, name)}: the dashboard will not serve TLS without it`
      );
    }
  }
  return ctx.problems;
}

function main(argv) {
  let mode = 'prestart';
  let configDir = '/etc/wazuh-dashboard';
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (['--install', '--upgrade', '--prestart', '--clear'].includes(arg)) {
      mode = arg.slice(2);
    } else if (arg === '-H' && argv[i + 1]) {
      configDir = path.resolve(argv[++i]);
    } else if (arg === '-h' || arg === '--help') {
      log('usage: resolve-credentials [--install|--upgrade|--prestart|--clear] [-H <config-dir>]');
      return 0;
    } else {
      err(`unknown option: ${arg}`);
      return 2;
    }
  }
  const failure = mode === 'install' || mode === 'upgrade' ? 0 : 1;
  if (process.getuid() !== 0) {
    err('must run as root');
    return failure;
  }
  const ctx = createContext({ home: path.resolve(__dirname, '..'), configDir });
  if (mode === 'clear') return clear(ctx);

  const problems = resolve(ctx, mode);
  if (mode !== 'prestart') return 0;
  // UNSAFE lines were printed when found.
  problems.filter((p) => !p.startsWith('UNSAFE ')).forEach(err);
  return problems.length ? 1 : 0;
}

module.exports = {
  createContext,
  readTrusted,
  writeTrusted,
  parseEnv,
  lookup,
  storesVerbatim,
  ymlHas,
  parseSans,
  mintCa,
  issueLeaf,
  validCa,
  resolve,
  clear,
};

if (require.main === module) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (e) {
    err(e.stack || String(e));
    process.exitCode =
      process.argv.includes('--install') || process.argv.includes('--upgrade') ? 0 : 1;
  }
}
