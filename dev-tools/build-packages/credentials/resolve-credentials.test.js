/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

// The resolver runs on the bundled Node outside the dashboard build, so this is a node:test file:
//   node --test dev-tools/build-packages/credentials/resolve-credentials.test.js
// The current user stands in for root.

const { test, mock } = require('node:test');
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

// Read on a host with eth0 and eth1 up (eth1 with two addresses), eth2 down, and a local range
// routed to lo.
const FIB_TRIE = `Main:
  +-- 0.0.0.0/0 3 0 4
     +-- 0.0.0.0/4 2 0 2
        |-- 0.0.0.0
           /0 universe UNICAST
        +-- 10.0.0.0/10 2 0 2
           |-- 10.9.9.9
              /32 host LOCAL
           |-- 10.50.0.0
              /24 host LOCAL
     +-- 127.0.0.0/8 2 0 2
        +-- 127.0.0.0/31 1 0 0
           |-- 127.0.0.0
              /8 host LOCAL
           |-- 127.0.0.1
              /32 host LOCAL
        |-- 127.255.255.255
           /32 link BROADCAST
     +-- 172.17.0.0/16 2 0 2
        +-- 172.17.0.0/30 2 0 2
           |-- 172.17.0.0
              /16 link UNICAST
           |-- 172.17.0.2
              /32 host LOCAL
        |-- 172.17.255.255
           /32 link BROADCAST
     +-- 192.168.56.0/24 2 0 1
        |-- 192.168.56.0
           /24 link UNICAST
        +-- 192.168.56.126/31 1 0 0
           |-- 192.168.56.126
              /32 host LOCAL
           |-- 192.168.56.127
              /32 host LOCAL
        |-- 192.168.56.255
           /32 link BROADCAST
Local:
  +-- 0.0.0.0/0 3 0 4
     +-- 0.0.0.0/4 2 0 2
        |-- 0.0.0.0
           /0 universe UNICAST
        +-- 10.0.0.0/10 2 0 2
           |-- 10.9.9.9
              /32 host LOCAL
           |-- 10.50.0.0
              /24 host LOCAL
     +-- 127.0.0.0/8 2 0 2
        +-- 127.0.0.0/31 1 0 0
           |-- 127.0.0.0
              /8 host LOCAL
           |-- 127.0.0.1
              /32 host LOCAL
        |-- 127.255.255.255
           /32 link BROADCAST
     +-- 172.17.0.0/16 2 0 2
        +-- 172.17.0.0/30 2 0 2
           |-- 172.17.0.0
              /16 link UNICAST
           |-- 172.17.0.2
              /32 host LOCAL
        |-- 172.17.255.255
           /32 link BROADCAST
     +-- 192.168.56.0/24 2 0 1
        |-- 192.168.56.0
           /24 link UNICAST
        +-- 192.168.56.126/31 1 0 0
           |-- 192.168.56.126
              /32 host LOCAL
           |-- 192.168.56.127
              /32 host LOCAL
        |-- 192.168.56.255
           /32 link BROADCAST
`;

// lo, a link-local, a usable, a deprecated, a tentative and a DAD-failed address.
const IF_INET6 = `00000000000000000000000000000001 01 80 10 80       lo
fe8000000000000070d1a2fffe571b29 03 40 20 80     eth1
fd000000000000000000000000000002 03 40 00 82     eth1
fd000000000000000000000000000001 03 40 00 a0     eth1
fd000000000000000000000000000003 03 40 00 c0     eth1
fd000000000000000000000000000004 03 40 00 88     eth1
`;

// Read on a host with two default routes: dA (metric 100, added last) and eth0 (metric 700).
const ROUTE = `Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
dA\t00000000\t016433C6\t0003\t0\t0\t100\t00000000\t0\t0\t0
eth0\t00000000\t010011AC\t0003\t0\t0\t700\t00000000\t0\t0\t0
eth0\t000011AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0
dA\t006433C6\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0
`;
const IPV6_ROUTE = `00000000000000000000000000000000 00 00000000000000000000000000000000 00 20010db8000000000000000000000001 00000064 00000001 00000000 00000003       dA
00000000000000000000000000000000 00 00000000000000000000000000000000 00 00000000000000000000000000000000 ffffffff 00000001 00000000 00200200       lo
`;

const v4 = (address) => ({ address, family: 'IPv4', internal: false });
const v6 = (address) => ({ address, family: 'IPv6', internal: false });

test('reads the default-route interfaces, preferred first', () => {
  assert.deepStrictEqual(r.parseDefaultRoutes(ROUTE, IPV6_ROUTE), ['dA', 'eth0']);
  assert.deepStrictEqual(r.parseDefaultRoutes('', ''), []);
});

test('reads the local IPv4 addresses from the kernel routing tables', () => {
  assert.deepStrictEqual(r.parseFibTrie(FIB_TRIE), [
    '10.9.9.9',
    '127.0.0.1',
    '172.17.0.2',
    '192.168.56.126',
    '192.168.56.127',
  ]);
  assert.deepStrictEqual(r.parseFibTrie(''), []);
});

test('reads the usable global IPv6 addresses', () => {
  assert.deepStrictEqual(r.parseIfInet6(IF_INET6), [
    { name: 'eth1', index: 3, address: 'fd00::2' },
  ]);
  assert.deepStrictEqual(r.parseIfInet6(''), []);
});

// The host of wazuh/wazuh-dashboard#1697: the default route on eth0, users on eth1.
function twoInterfaces() {
  return {
    interfaces: {
      lo: [{ address: '127.0.0.1', family: 'IPv4', internal: true }],
      eth1: [v4('192.168.56.126')],
      eth0: [v4('10.0.2.15'), v6('fd17::1')],
    },
    defaultRoute: ['eth0'],
    fibTrie: `Local:
  +-- 0.0.0.0/0 3 0 4
     |-- 10.0.2.15
        /32 host LOCAL
     |-- 192.168.56.126
        /32 host LOCAL
`,
    ifInet6: 'fd170000000000000000000000000001 02 40 00 80     eth0\n',
  };
}

test('discovers every interface, the default-route one first', () => {
  assert.deepStrictEqual(r.discoverAddresses(twoInterfaces()), [
    '10.0.2.15',
    'fd17::1',
    '192.168.56.126',
  ]);
});

test('orders the default-route interfaces by route preference', () => {
  const host = {
    interfaces: { eth0: [v4('172.17.0.2')], dA: [v4('198.51.100.10')], 'eth1:1': [v4('10.1.1.1')] },
    defaultRoute: ['dA', 'eth1', 'eth0'],
  };
  assert.deepStrictEqual(r.discoverAddresses(host), ['198.51.100.10', '10.1.1.1', '172.17.0.2']);
});

test('keeps the order of the IPv6 addresses of the interfaces that are up', () => {
  // if_inet6 lists them in hash order; dX (index 5) is down.
  const ifInet6 = [
    '20010db8000000000000000000000030 05 40 00 80       dX',
    '20010db8000000000000000000000020 04 40 00 80       d6',
    '20010db8aaaa00000000000000000001 04 40 00 80       d6',
    '20010db8000000000000000000000010 04 40 00 80       d6',
    '20010db8000000000000000000000040 03 40 00 80       dY',
  ].join('\n');
  const host = {
    interfaces: { d6: [v6('2001:db8:aaaa::1'), v6('2001:0db8::10'), v6('2001:db8::20')] },
    defaultRoute: ['d6'],
    fibTrie: '',
    ifInet6,
  };
  assert.deepStrictEqual(r.discoverAddresses(host), [
    '2001:db8:aaaa::1',
    '2001:db8::10',
    '2001:db8::20',
    '2001:db8::40',
    '2001:db8::30',
  ]);
});

test('discovers the addresses of interfaces that are down', () => {
  const warnings = [];
  const addresses = r.discoverAddresses({
    interfaces: {
      eth0: [v4('172.17.0.2')],
      eth1: [v4('192.168.56.126'), v4('192.168.56.127'), v6('fd00::2'), v6('fd00::1')],
    },
    fibTrie: FIB_TRIE,
    ifInet6: IF_INET6,
    warn: (msg) => warnings.push(msg),
  });
  // Down ones included; loopback, the routed range and the deprecated IPv6 left out.
  assert.deepStrictEqual(addresses, [
    '172.17.0.2',
    '192.168.56.126',
    '192.168.56.127',
    '10.9.9.9',
    'fd00::2',
  ]);
  assert.deepStrictEqual(warnings, []);
});

test('keeps the up interfaces when the routing tables cannot be read', () => {
  for (const fibTrie of [null, 'a format this parser does not know']) {
    const warnings = [];
    const host = { ...twoInterfaces(), fibTrie, warn: (msg) => warnings.push(msg) };
    assert.deepStrictEqual(r.discoverAddresses(host), ['10.0.2.15', 'fd17::1', '192.168.56.126']);
    assert.strictEqual(warnings.length, 1);
  }
});

test('takes the IPv6 addresses of the up interfaces when if_inet6 cannot be read', () => {
  const host = { ...twoInterfaces(), ifInet6: null };
  host.interfaces.eth1.push(v6('fe80::1'));
  assert.deepStrictEqual(r.discoverAddresses(host), ['10.0.2.15', 'fd17::1', '192.168.56.126']);
  assert.deepStrictEqual(r.discoverAddresses(), []);
});

test('issues the certificate when discovery finds nothing or fails', () => {
  const { ctx } = setup();
  // A host name nothing resolves, so no FQDN is added.
  const host = 'resolver-test-1697';
  const loopback = ['DNS:localhost', 'IP:127.0.0.1', 'IP:::1'];
  const run = (discover) => {
    const stderr = [];
    mock.method(process.stderr, 'write', (line) => stderr.push(line));
    try {
      const names = r.leafSans(ctx, host, discover).map((s) => `${s.type}:${s.value}`);
      return { names, stderr: stderr.join('') };
    } finally {
      mock.restoreAll();
    }
  };
  const none = run(() => []);
  assert.deepStrictEqual(none.names, [`DNS:${host}`, ...loopback]);
  assert.match(none.stderr, /found no address of this host.*WAZUH_DASHBOARD_CERT_SANS/);
  const failed = run(() => {
    throw new Error('boom');
  });
  assert.deepStrictEqual(failed.names, [`DNS:${host}`, ...loopback]);
  assert.match(failed.stderr, /could not discover the addresses of this host: boom/);
  const found = run(() => ['192.168.56.126']);
  assert.deepStrictEqual(found.names, [`DNS:${host}`, 'IP:192.168.56.126', ...loopback]);
  assert.strictEqual(found.stderr, '');
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
