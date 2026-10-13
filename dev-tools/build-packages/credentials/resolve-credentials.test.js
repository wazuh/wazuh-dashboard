/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

// The resolver runs on the bundled Node outside the dashboard build, so this is a node:test file:
//   node --test dev-tools/build-packages/credentials/
// The current user stands in for root.

const { test } = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');
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
  };
  peers[1] = {
    ...peers[1],
    key: 'WAZUH_MANAGER_WUI_PASSWORD',
    alias: 'API_PASSWORD',
    account: 'wazuh-internal-client',
    entry: 'wazuh_core.hosts.default.password',
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

  // The manager is not installed yet: its password is missing.
  let problems = r.resolve(ctx, 'install');
  assert.deepStrictEqual(
    problems.filter((p) => p.startsWith('MISSING')),
    ['MISSING WAZUH_MANAGER_WUI_PASSWORD (wazuh-internal-client)']
  );
  assert.strictEqual(store.get('opensearch.password'), 'Kibana.Pass1');
  assert.strictEqual(store.get('opensearch.username'), 'kibanaserver');
  assert.strictEqual(store.get('wazuh_ai_assistant.encryptionKey').length, 44);

  const certs = path.join(configDir, 'certs');
  const dashCert = new crypto.X509Certificate(fs.readFileSync(path.join(certs, 'dashboard.pem')));
  const ownCa = fs.readFileSync(path.join(configDir, 'ca', 'root-ca.pem'));
  assert.ok(dashCert.verify(new crypto.X509Certificate(ownCa).publicKey));
  assert.deepStrictEqual(fs.readFileSync(path.join(configDir, 'export', 'ca.pem')), ownCa);
  assert.ok(fs.existsSync(path.join(configDir, 'ca', '.wazuh-dashboard-bootstrap-ca')));
  assert.strictEqual(fs.statSync(path.join(certs, 'dashboard-key.pem')).mode & 0o777, 0o640);
  assert.strictEqual(
    fs.readFileSync(path.join(certs, 'root-ca.pem'), 'utf8'),
    indexerCa.trim() + '\n'
  );

  // The manager arrives; the next start picks up its password and CA.
  const managerCa = caPair().certPem;
  fs.writeFileSync(
    path.join(peers[1].exportDir, 'credentials.env'),
    'WAZUH_MANAGER_WUI_PASSWORD=Wui.Pass1\n'
  );
  fs.writeFileSync(path.join(peers[1].exportDir, 'ca.pem'), managerCa);
  const pair = fs.readFileSync(path.join(certs, 'dashboard.pem'));
  ctx.problems = [];
  problems = r.resolve(ctx, 'prestart');
  assert.deepStrictEqual(problems, []);
  assert.strictEqual(store.get('wazuh_core.hosts.default.password'), 'Wui.Pass1');
  assert.strictEqual(
    fs.readFileSync(path.join(certs, 'root-ca.pem'), 'utf8'),
    indexerCa.trim() + '\n' + managerCa.trim() + '\n'
  );
  assert.deepStrictEqual(fs.readFileSync(path.join(certs, 'dashboard.pem')), pair);

  // --clear removes what the resolver stored, issued and minted.
  assert.strictEqual(r.clear(ctx), 0);
  assert.strictEqual(store.size, 0);
  for (const gone of ['certs', 'ca', 'export'])
    assert.ok(!fs.existsSync(path.join(configDir, gone)));
});

test("an operator's root-ca.pem and staged CA are kept", () => {
  const { configDir, ctx } = setup();
  const certs = path.join(configDir, 'certs');
  fs.mkdirSync(certs, { mode: 0o750 });
  fs.writeFileSync(path.join(certs, 'root-ca.pem'), 'operator\n');
  const staged = caPair();
  fs.mkdirSync(path.join(configDir, 'ca'), { mode: 0o700 });
  fs.writeFileSync(path.join(configDir, 'ca', 'root-ca.pem'), staged.certPem);
  fs.writeFileSync(path.join(configDir, 'ca', 'root-ca.key'), staged.keyPem, { mode: 0o400 });
  r.resolve(ctx, 'install');
  assert.strictEqual(fs.readFileSync(path.join(certs, 'root-ca.pem'), 'utf8'), 'operator\n');
  const leaf = new crypto.X509Certificate(fs.readFileSync(path.join(certs, 'dashboard.pem')));
  assert.ok(leaf.verify(new crypto.X509Certificate(staged.certPem).publicKey));
  r.clear(ctx);
  assert.ok(fs.existsSync(path.join(configDir, 'ca', 'root-ca.key')));
  assert.strictEqual(fs.readFileSync(path.join(certs, 'root-ca.pem'), 'utf8'), 'operator\n');
});

test('half a pair is refused', () => {
  const { configDir, ctx } = setup();
  fs.mkdirSync(path.join(configDir, 'certs'), { mode: 0o750 });
  fs.writeFileSync(path.join(configDir, 'certs', 'dashboard.pem'), 'x');
  r.resolve(ctx, 'install');
  assert.ok(!fs.existsSync(path.join(configDir, 'certs', 'dashboard-key.pem')));
  assert.ok(!fs.existsSync(path.join(configDir, 'ca')));
});
