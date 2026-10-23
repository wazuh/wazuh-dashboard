/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

// The resolver runs on the bundled Node outside the dashboard build, so this is a node:test file:
//   node --test dev-tools/build-packages/credentials/resolve-credentials.test.js
// The current user stands in for root.

const { test } = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const forge = require('node-forge');
const r = require('./resolve-credentials.js');

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'resolver-'));
  fs.chmodSync(root, 0o755);
  const configDir = path.join(root, 'wazuh-dashboard');
  fs.mkdirSync(configDir, { mode: 0o750 });
  const peers = ['indexer', 'manager'].map((name) => {
    const exportDir = path.join(root, `wazuh-${name}`, 'export');
    fs.mkdirSync(exportDir, { recursive: true, mode: 0o700 });
    return { name, exportDir };
  });
  peers[0] = {
    ...peers[0],
    key: 'WAZUH_INDEXER_KIBANASERVER_PASSWORD',
    alias: 'INDEXER_PASSWORD',
    account: 'kibanaserver',
    entry: 'opensearch.password',
    username: { entry: 'opensearch.username', value: 'kibanaserver' },
    required: true,
    caMissing: 'no indexer CA',
  };
  peers[1] = {
    ...peers[1],
    key: 'WAZUH_MANAGER_WUI_PASSWORD',
    alias: 'API_PASSWORD',
    account: 'wazuh-internal-client',
    entry: 'wazuh_core.hosts.default.password',
    required: false,
    caMissing: 'no manager CA',
  };
  const ctx = r.createContext({
    home: root,
    configDir,
    rootUid: process.getuid(),
    rootGid: process.getgid(),
    peers,
    env: {},
  });
  ctx.gid = process.getgid();
  // An in-memory keystore with the CLI's behaviour: `add` never overwrites.
  const store = new Map();
  const ks = path.join(configDir, 'opensearch_dashboards.keystore');
  ctx.runKeystore = ([cmd, key], input) => {
    if (cmd === 'create') fs.writeFileSync(ks, '', { mode: 0o600 });
    if (cmd === 'add' && !store.has(key)) store.set(key, input);
    if (cmd === 'remove') store.delete(key);
    return { ok: true, stdout: [...store.keys()].join('\n') };
  };
  return { root, configDir, peers, ctx, store };
}

function caPair() {
  return r.mintCa(forge, 'peer');
}

test('parses env files and checks verbatim storage', () => {
  assert.deepStrictEqual(r.parseEnv('# c\nA=1\nB="x=y"\n\nC=\n'), { A: '1', B: 'x=y', C: '' });
  assert.ok(r.storesVerbatim('S3cret.Pass_word'));
  for (const bad of ['123', 'true', '"q"', ' pad', '[1]']) assert.ok(!r.storesVerbatim(bad));
});

test('parses and validates SANs', () => {
  assert.deepStrictEqual(r.parseSans('DNS:a.example,IP:10.0.0.1,b,::1,A.example'), [
    { type: 'DNS', value: 'a.example' },
    { type: 'IP', value: '10.0.0.1' },
    { type: 'DNS', value: 'b' },
    { type: 'IP', value: '::1' },
  ]);
  assert.throws(() => r.parseSans('IP:999.1.1.1'));
  assert.throws(() => r.parseSans('DNS:bad name'));
});

test('issues a leaf the CA verifies, with the SANs asked for', () => {
  const ca = caPair();
  assert.ok(r.validCa(ca.certPem, ca.keyPem));
  const sans = r.parseSans('DNS:host,IP:10.0.0.1,IP:::1');
  const leaf = r.issueLeaf(forge, ca.certPem, ca.keyPem, 'host', sans);
  const cert = new crypto.X509Certificate(leaf.certPem);
  assert.ok(cert.verify(new crypto.X509Certificate(ca.certPem).publicKey));
  assert.ok(cert.checkPrivateKey(crypto.createPrivateKey(leaf.keyPem)));
  assert.match(cert.subjectAltName, /DNS:host, IP Address:10\.0\.0\.1, IP Address:0:0:0:0:0:0:0:1/);
  assert.ok(!cert.ca);
});

test('reports and refuses unsafe files', () => {
  const { root, ctx } = setup();
  const target = path.join(root, 'target');
  fs.writeFileSync(target, 'A=1\n');
  const link = path.join(ctx.configDir, 'local.env');
  fs.symlinkSync(target, link);
  assert.strictEqual(r.readTrusted(ctx, link), null);
  fs.unlinkSync(link);
  fs.writeFileSync(link, 'A=1\n', { mode: 0o666 });
  fs.chmodSync(link, 0o666);
  assert.strictEqual(r.readTrusted(ctx, link), null);
  assert.deepStrictEqual(
    ctx.problems.map((p) => p.replace(/ .*: /, ' ')),
    ['UNSAFE it is a symbolic link', 'UNSAFE it is group- or world-writable']
  );
});

test('looks values up in the environment, then local.env, then the publisher', () => {
  const { ctx, peers } = setup();
  fs.writeFileSync(path.join(peers[0].exportDir, 'credentials.env'), 'K=peer\n');
  assert.strictEqual(r.lookup(ctx, 'K', null, peers[0].exportDir).value, 'peer');
  fs.writeFileSync(path.join(ctx.configDir, 'local.env'), 'K=local\n', { mode: 0o600 });
  assert.strictEqual(r.lookup(ctx, 'K', null, peers[0].exportDir).value, 'local');
  ctx.env.ALIAS = 'env';
  assert.strictEqual(r.lookup(ctx, 'K', 'ALIAS', peers[0].exportDir).value, 'env');
});

test('install resolves everything from the peers; a restart changes nothing', () => {
  const { configDir, peers, ctx, store } = setup();
  ctx.env.WAZUH_DASHBOARD_CERT_SANS = 'DNS:dash,IP:10.0.0.5';
  const indexerCa = caPair().certPem;
  fs.writeFileSync(
    path.join(peers[0].exportDir, 'credentials.env'),
    'WAZUH_INDEXER_KIBANASERVER_PASSWORD=Kibana.Pass1\n'
  );
  fs.writeFileSync(path.join(peers[0].exportDir, 'ca.pem'), indexerCa);
  fs.writeFileSync(
    path.join(configDir, 'opensearch_dashboards.yml'),
    'wazuh_core.hosts:\n  default:\n    url: https://localhost\n'
  );

  // The manager is not installed yet: its password and CA are only warnings, so the dashboard
  // starts and serves the indexer data.
  let problems = r.resolve(ctx, 'install');
  assert.deepStrictEqual(problems, []);
  assert.deepStrictEqual(r.resolve(ctx, 'prestart'), []);
  assert.ok(!store.has('wazuh_core.hosts.default.password'));
  assert.strictEqual(store.get('opensearch.password'), 'Kibana.Pass1');
  assert.strictEqual(store.get('opensearch.username'), 'kibanaserver');
  assert.strictEqual(store.get('wazuh_ai_assistant.encryptionKey').length, 44);

  const certs = path.join(configDir, 'certs');
  const chain = fs.readFileSync(path.join(certs, 'dashboard.pem'), 'utf8');
  const ownCa = fs.readFileSync(path.join(configDir, 'ca', 'root-ca.pem'), 'utf8');
  const dashCert = new crypto.X509Certificate(chain);
  assert.ok(dashCert.verify(new crypto.X509Certificate(ownCa).publicKey));
  assert.ok(chain.endsWith(ownCa), 'dashboard.pem carries the leaf followed by the CA');
  assert.ok(Date.parse(dashCert.validFrom) < Date.now() - 23 * 60 * 60 * 1000, 'backdated');
  assert.strictEqual(fs.readFileSync(path.join(configDir, 'export', 'ca.pem'), 'utf8'), ownCa);
  assert.ok(fs.existsSync(path.join(configDir, 'ca', '.wazuh-dashboard-bootstrap-ca')));
  assert.strictEqual(fs.statSync(path.join(certs, 'dashboard-key.pem')).mode & 0o777, 0o640);
  assert.strictEqual(fs.readFileSync(path.join(certs, 'indexer-ca.pem'), 'utf8'), indexerCa);
  assert.ok(fs.existsSync(path.join(certs, '.indexer-ca.imported')));
  assert.ok(!fs.existsSync(path.join(certs, 'root-ca.pem')), 'no merged bundle');

  // The manager arrives; the next start picks up its password and CA.
  const managerCa = caPair().certPem;
  fs.writeFileSync(
    path.join(peers[1].exportDir, 'credentials.env'),
    'WAZUH_MANAGER_WUI_PASSWORD=Wui.Pass1\n'
  );
  fs.writeFileSync(path.join(peers[1].exportDir, 'ca.pem'), managerCa);
  ctx.problems = [];
  problems = r.resolve(ctx, 'prestart');
  assert.deepStrictEqual(problems, []);
  assert.strictEqual(store.get('wazuh_core.hosts.default.password'), 'Wui.Pass1');
  assert.strictEqual(fs.readFileSync(path.join(certs, 'manager-ca.pem'), 'utf8'), managerCa);
  assert.strictEqual(fs.readFileSync(path.join(certs, 'dashboard.pem'), 'utf8'), chain);

  // A reinstalled indexer publishes a new CA: the import follows it.
  const newIndexerCa = caPair().certPem;
  fs.writeFileSync(path.join(peers[0].exportDir, 'ca.pem'), newIndexerCa);
  r.resolve(ctx, 'prestart');
  assert.strictEqual(fs.readFileSync(path.join(certs, 'indexer-ca.pem'), 'utf8'), newIndexerCa);

  // --clear removes what the resolver stored, issued, imported and minted.
  assert.strictEqual(r.clear(ctx), 0);
  assert.strictEqual(store.size, 0);
  for (const gone of ['certs', 'ca', 'export']) {
    assert.ok(!fs.existsSync(path.join(configDir, gone)));
  }
});

test('a staged peer CA and a staged dashboard CA are used and kept', () => {
  const { configDir, peers, ctx } = setup();
  const certs = path.join(configDir, 'certs');
  fs.mkdirSync(certs, { mode: 0o750 });
  const stagedIndexerCa = caPair().certPem;
  fs.writeFileSync(path.join(certs, 'indexer-ca.pem'), stagedIndexerCa);
  fs.writeFileSync(path.join(peers[0].exportDir, 'ca.pem'), caPair().certPem);
  const staged = caPair();
  fs.mkdirSync(path.join(configDir, 'ca'), { mode: 0o700 });
  fs.writeFileSync(path.join(configDir, 'ca', 'root-ca.pem'), staged.certPem);
  fs.writeFileSync(path.join(configDir, 'ca', 'root-ca.key'), staged.keyPem, { mode: 0o400 });

  r.resolve(ctx, 'install');
  assert.strictEqual(fs.readFileSync(path.join(certs, 'indexer-ca.pem'), 'utf8'), stagedIndexerCa);
  const leaf = new crypto.X509Certificate(fs.readFileSync(path.join(certs, 'dashboard.pem')));
  assert.ok(leaf.verify(new crypto.X509Certificate(staged.certPem).publicKey));

  r.clear(ctx);
  assert.ok(fs.existsSync(path.join(configDir, 'ca', 'root-ca.key')));
  assert.strictEqual(fs.readFileSync(path.join(certs, 'indexer-ca.pem'), 'utf8'), stagedIndexerCa);
});

test('a staged peer CA that is not a CA certificate is INVALID', () => {
  const { configDir, ctx } = setup();
  const certs = path.join(configDir, 'certs');
  fs.mkdirSync(certs, { mode: 0o750 });
  const ca = caPair();
  const leaf = r.issueLeaf(forge, ca.certPem, ca.keyPem, 'x', r.parseSans('DNS:x'));
  fs.writeFileSync(path.join(certs, 'indexer-ca.pem'), leaf.certPem);
  const problems = r.resolve(ctx, 'prestart');
  assert.ok(
    problems.includes(
      `INVALID ${path.join(certs, 'indexer-ca.pem')}: it is not a valid, current CA certificate`
    )
  );
});

test('an empty WAZUH_DASHBOARD_CERT_SANS is refused', () => {
  const { configDir, ctx } = setup();
  fs.writeFileSync(path.join(configDir, 'local.env'), 'WAZUH_DASHBOARD_CERT_SANS=\n', {
    mode: 0o600,
  });
  r.resolve(ctx, 'install');
  assert.ok(!fs.existsSync(path.join(configDir, 'certs', 'dashboard.pem')));
});

test('half a pair is refused', () => {
  const { configDir, ctx } = setup();
  fs.mkdirSync(path.join(configDir, 'certs'), { mode: 0o750 });
  fs.writeFileSync(path.join(configDir, 'certs', 'dashboard.pem'), 'x');
  r.resolve(ctx, 'install');
  assert.ok(!fs.existsSync(path.join(configDir, 'certs', 'dashboard-key.pem')));
  assert.ok(!fs.existsSync(path.join(configDir, 'ca')));
});

test('prestart reports a planted file in certs/ as UNSAFE', () => {
  const { configDir, ctx } = setup();
  const certs = path.join(configDir, 'certs');
  fs.mkdirSync(certs, { mode: 0o750 });
  fs.writeFileSync(path.join(certs, 'dashboard.pem'), 'x');
  fs.chmodSync(path.join(certs, 'dashboard.pem'), 0o666);
  const problems = r.resolve(ctx, 'prestart');
  assert.ok(
    problems.includes(`UNSAFE ${path.join(certs, 'dashboard.pem')}: it is group- or world-writable`)
  );
});

test('prestart checks local.env even when nothing is left to read from it', () => {
  const { configDir, ctx } = setup();
  fs.writeFileSync(path.join(configDir, 'local.env'), 'X=1\n');
  fs.chmodSync(path.join(configDir, 'local.env'), 0o666);
  const problems = r.resolve(ctx, 'prestart');
  assert.ok(
    problems.includes(`UNSAFE ${path.join(configDir, 'local.env')}: it is group- or world-writable`)
  );
});

test('a world-readable local.env is read; only writable by others is UNSAFE', () => {
  const { configDir, ctx } = setup();
  const file = path.join(configDir, 'local.env');
  fs.writeFileSync(file, 'K=local\n');
  // What a umask of 022 leaves.
  fs.chmodSync(file, 0o644);
  assert.strictEqual(r.lookup(ctx, 'K', null, null).value, 'local');
  assert.deepStrictEqual(ctx.problems, []);
});

test('--clear keeps a pair and keystore entries the resolver did not set', () => {
  const { configDir, peers, ctx, store } = setup();
  fs.writeFileSync(
    path.join(peers[0].exportDir, 'credentials.env'),
    'WAZUH_INDEXER_KIBANASERVER_PASSWORD=Kibana.Pass1\n'
  );
  // The operator's own entry and pair, from a PKI that is not the dashboard's.
  store.set('opensearch.password', 'Operator.Pass1');
  const certs = path.join(configDir, 'certs');
  fs.mkdirSync(certs, { mode: 0o750 });
  const external = caPair();
  const pair = r.issueLeaf(forge, external.certPem, external.keyPem, 'x', r.parseSans('DNS:x'));
  fs.writeFileSync(path.join(certs, 'dashboard.pem'), pair.certPem);
  fs.writeFileSync(path.join(certs, 'dashboard-key.pem'), pair.keyPem);

  r.resolve(ctx, 'install');
  assert.strictEqual(store.get('opensearch.password'), 'Operator.Pass1');
  assert.ok(store.has('wazuh_ai_assistant.encryptionKey'));

  assert.strictEqual(r.clear(ctx), 0);
  assert.deepStrictEqual([...store.keys()], ['opensearch.password']);
  assert.strictEqual(fs.readFileSync(path.join(certs, 'dashboard.pem'), 'utf8'), pair.certPem);
  assert.ok(fs.existsSync(path.join(certs, 'dashboard-key.pem')));
  assert.ok(!fs.existsSync(path.join(configDir, '.resolved-keystore-entries')));
});

const COOKIE = 'opensearch_security.cookie.password';

// Everything the resolver writes to stdout and stderr while fn runs.
function captureOutput(fn) {
  const out = [];
  const writes = [process.stdout.write, process.stderr.write];
  process.stdout.write = process.stderr.write = (chunk) => out.push(String(chunk)) > 0;
  try {
    fn();
  } finally {
    [process.stdout.write, process.stderr.write] = writes;
  }
  return out.join('');
}

test('install generates the cookie password; later starts never rotate it', () => {
  const { ctx, store } = setup();
  r.resolve(ctx, 'install');
  const generated = store.get(COOKIE);
  assert.strictEqual(generated.length, 44);
  assert.strictEqual(Buffer.from(generated, 'base64').length, 32);
  r.resolve(ctx, 'prestart');
  r.resolve(ctx, 'prestart');
  assert.strictEqual(store.get(COOKIE), generated);
});

test('an upgrade generates no owned secret; the first start does', () => {
  const { ctx, store } = setup();
  r.resolve(ctx, 'upgrade');
  assert.ok(!store.has(COOKIE));
  assert.ok(!store.has('wazuh_ai_assistant.encryptionKey'));
  r.resolve(ctx, 'prestart');
  assert.strictEqual(store.get(COOKIE).length, 44);
});

test('a cookie password already in the keystore or the yml is never replaced', () => {
  const inKeystore = setup();
  inKeystore.store.set(COOKIE, 'Operator-Cookie-Password-0123456789');
  r.resolve(inKeystore.ctx, 'install');
  r.resolve(inKeystore.ctx, 'prestart');
  assert.strictEqual(inKeystore.store.get(COOKIE), 'Operator-Cookie-Password-0123456789');

  const inYml = setup();
  fs.writeFileSync(
    path.join(inYml.configDir, 'opensearch_dashboards.yml'),
    `${COOKIE}: Yml-Cookie-Password-0123456789abcdef\n`
  );
  r.resolve(inYml.ctx, 'install');
  r.resolve(inYml.ctx, 'prestart');
  assert.ok(!inYml.store.has(COOKIE));
});

test('--clear removes a generated cookie password and keeps an operator one', () => {
  const generated = setup();
  r.resolve(generated.ctx, 'install');
  assert.ok(generated.store.has(COOKIE));
  assert.strictEqual(r.clear(generated.ctx), 0);
  assert.ok(!generated.store.has(COOKIE));

  const operator = setup();
  operator.store.set(COOKIE, 'Operator-Cookie-Password-0123456789');
  r.resolve(operator.ctx, 'install');
  assert.strictEqual(r.clear(operator.ctx), 0);
  assert.strictEqual(operator.store.get(COOKIE), 'Operator-Cookie-Password-0123456789');
});

test('the cookie password is never printed', () => {
  const { ctx, store } = setup();
  ctx.verbose = true;
  const output = captureOutput(() => {
    r.resolve(ctx, 'install');
    r.resolve(ctx, 'prestart');
  });
  assert.match(output, new RegExp(`generated ${COOKIE}`));
  assert.ok(!output.includes(store.get(COOKIE)));
});

test('failing to generate the cookie password is a warning; the start goes on', () => {
  const { ctx, store } = setup();
  const runKeystore = ctx.runKeystore;
  ctx.runKeystore = (args, input) =>
    args[0] === 'add' && args[1] === COOKIE ? { ok: false, stdout: '' } : runKeystore(args, input);
  let problems;
  const output = captureOutput(() => {
    problems = r.resolve(ctx, 'prestart');
  });
  assert.ok(!store.has(COOKIE));
  assert.match(output, new RegExp(`warning: could not generate ${COOKIE}`));
  assert.ok(!problems.some((p) => p.includes(COOKIE)));
  assert.ok(store.has('wazuh_ai_assistant.encryptionKey'));
});

test('a staged dashboard CA without an RSA key is refused', () => {
  const { configDir, ctx } = setup();
  const ca = path.join(configDir, 'ca');
  fs.mkdirSync(ca, { mode: 0o700 });
  // forge cannot build an EC certificate, so openssl stages it.
  execFileSync(
    'openssl',
    [
      'req',
      '-x509',
      '-newkey',
      'ec',
      '-pkeyopt',
      'ec_paramgen_curve:prime256v1',
      '-nodes',
      '-subj',
      '/CN=ec-ca',
      '-days',
      '1',
      '-addext',
      'basicConstraints=critical,CA:TRUE',
      '-addext',
      'keyUsage=critical,keyCertSign',
      '-keyout',
      path.join(ca, 'root-ca.key'),
      '-out',
      path.join(ca, 'root-ca.pem'),
    ],
    { stdio: 'ignore' }
  );
  fs.chmodSync(path.join(ca, 'root-ca.key'), 0o400);
  fs.chmodSync(path.join(ca, 'root-ca.pem'), 0o644);
  r.resolve(ctx, 'install');
  assert.ok(!fs.existsSync(path.join(configDir, 'certs', 'dashboard.pem')));
});
