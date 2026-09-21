/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * Check Prettier formatting on the lines a change writes.
 *
 * Most of this repository comes from OpenSearch Dashboards, which never ran
 * Prettier over its own tree. About 10% of the files have never been formatted,
 * and no configuration or Prettier version makes them pass. Reformatting a
 * whole file because a change touched two lines rewrites that upstream code,
 * and every rewritten file then conflicts in the next upward merge, the next
 * cherry-pick between version branches, and the next OpenSearch migration.
 *
 * So a change answers for the lines it writes and nothing else. A file it adds
 * is checked in full. A line it did not touch is never checked.
 *
 * Usage:
 *   node scripts/prettier-check-changed.js --base <ref> [--base <ref>] [--fix] <file>...
 *   node scripts/prettier-check-changed.js --staged [--fix] <file>...
 *
 * Pass several --base refs and a line counts as written by the change only when
 * it differs from all of them. A merge needs that: the lines it carries over
 * from the branch being merged were written there, not here.
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
let prettier;
try {
  prettier = require('prettier');
} catch (e) {
  console.error('Prettier is not installed. Run the dependency install step before this check.');
  process.exit(2);
}

const git = (...args) =>
  execFileSync('git', args, {
    encoding: 'utf8',
    maxBuffer: 1 << 28,
    // Capture stderr rather than inheriting it. Probing for a path that does
    // not exist at a base ref is expected and should stay quiet.
    stdio: ['ignore', 'pipe', 'pipe'],
  });

// `git diff --no-index` exits 1 when the files differ, which is the normal case
// here, so a non-zero status still carries the diff we need.
const gitQuiet = (...args) => {
  try {
    return git(...args);
  } catch (e) {
    return typeof e.stdout === 'string' && e.stdout.length > 0 ? e.stdout : null;
  }
};

/** Parse `@@ -a,b +c,d @@` headers into inclusive line ranges on one side. */
function hunkRanges(diff, side) {
  const re = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/gm;
  const out = [];
  let m;
  while ((m = re.exec(diff)) !== null) {
    const start = Number(side === 'new' ? m[3] : m[1]);
    const count = Number((side === 'new' ? m[4] : m[2]) ?? 1);
    if (count > 0) out.push([start, start + count - 1]);
  }
  return out;
}

const overlaps = (a, b) => a.some(([s, e]) => b.some(([t, f]) => s <= f && t <= e));

/** Ranges covered by both lists. Narrows a merge to the lines no parent has. */
const intersect = (a, b) => {
  const out = [];
  for (const [s, e] of a) {
    for (const [t, f] of b) {
      const lo = Math.max(s, t);
      const hi = Math.min(e, f);
      if (lo <= hi) out.push([lo, hi]);
    }
  }
  return out;
};

function main() {
  const argv = process.argv.slice(2);
  const bases = [];
  const files = [];
  let staged = false;
  let fix = false;

  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--base') bases.push(argv[++i]);
    else if (argv[i] === '--staged') staged = true;
    else if (argv[i] === '--fix') fix = true;
    else files.push(argv[i]);
  }
  if (!staged && bases.length === 0) {
    console.error('usage: prettier-check-changed.js (--base <ref> | --staged) [--fix] <file>...');
    process.exit(2);
  }
  if (files.length === 0) {
    console.log('No files to check.');
    return;
  }

  for (const ref of bases) {
    if (gitQuiet('rev-parse', '--verify', '--quiet', `${ref}^{commit}`) === null) {
      console.error(
        `Base ref "${ref}" could not be resolved. Refusing to check, because ` +
          'with no base every line looks unchanged and the check would silently pass.'
      );
      process.exit(2);
    }
  }

  const root = git('rev-parse', '--show-toplevel').trim();
  const rel = (f) => path.relative(root, path.resolve(f));

  // Follow renames so moving an upstream file does not count as writing it.
  const renames = new Map();
  if (!staged) {
    const ns = gitQuiet('diff', '--name-status', '--find-renames', bases[0]) || '';
    for (const line of ns.split('\n')) {
      const p = line.split('\t');
      if (p[0] && p[0].startsWith('R') && p.length === 3) renames.set(p[2], p[1]);
    }
  }

  const problems = [];

  const skipped = [];

  for (const raw of files) {
    try {
      const file = rel(raw);
      const abs = path.join(root, file);
      if (!fs.existsSync(abs)) continue;

      const info = prettier.getFileInfo.sync(abs, {
        resolveConfig: true,
        ignorePath: path.join(root, '.prettierignore'),
      });
      if (info.ignored || !info.inferredParser) continue;

      const source = fs.readFileSync(abs, 'utf8');
      const options = { ...prettier.resolveConfig.sync(abs), filepath: abs };

      let formatted;
      try {
        formatted = prettier.format(source, options);
      } catch (e) {
        continue; // unparseable (e.g. .eslintrc is YAML but inferred as JSON)
      }
      if (formatted && typeof formatted.then === 'function') {
        console.error(
          'This Prettier returns a promise from format(), which means Prettier 3 ' +
            'or newer. This script only supports Prettier 2. Update it before bumping.'
        );
        process.exit(2);
      }
      if (formatted === source) continue;

      // Lines this change wrote: those differing from every base. A file that
      // does not exist at a base is new there, so all its lines count.
      let written = null;
      const refs = staged ? ['--cached'] : bases;
      for (const ref of refs) {
        const src = renames.get(file) || file;
        const existed = staged || gitQuiet('cat-file', '-e', `${ref}:${src}`) !== null;
        let d = null;
        if (existed && staged) {
          d = gitQuiet('diff', '--unified=0', '--cached', '--', file);
        } else if (existed) {
          d = gitQuiet('diff', '--unified=0', '--find-renames', ref, '--', file);
        }
        const ranges =
          existed && d !== null ? hunkRanges(d, 'new') : [[1, source.split('\n').length]];
        written = written === null ? ranges : intersect(written, ranges);
      }
      if (!written || written.length === 0) continue;

      const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'pcc-')), path.basename(file));
      fs.writeFileSync(tmp, formatted);
      const fdiff =
        gitQuiet('diff', '--no-index', '--unified=0', '--no-color', '--', abs, tmp) || '';
      fs.rmSync(path.dirname(tmp), { recursive: true, force: true });
      const wanted = hunkRanges(fdiff, 'old');

      const hits = wanted.filter((w) => overlaps([w], written));
      if (hits.length === 0) continue;

      if (fix) {
        const src = source.split('\n');
        const dst = formatted.split('\n');
        const re = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/gm;
        const all = [];
        let m;
        while ((m = re.exec(fdiff)) !== null) {
          all.push({
            os: Number(m[1]),
            oc: Number(m[2] ?? 1),
            ns: Number(m[3]),
            nc: Number(m[4] ?? 1),
          });
        }
        const keep = all.filter((h) => h.oc > 0 && overlaps([[h.os, h.os + h.oc - 1]], written));
        for (const h of keep.reverse()) {
          src.splice(h.os - 1, h.oc, ...dst.slice(h.ns - 1, h.ns - 1 + h.nc));
        }
        fs.writeFileSync(abs, src.join('\n'));
        console.log(`fixed  ${file} (${keep.length} hunk${keep.length === 1 ? '' : 's'})`);
      } else {
        problems.push({ file, hits });
      }
    } catch (e) {
      // One unreadable or unusual file must not fail the job.
      skipped.push(`${raw}: ${e.message.split('\n')[0]}`);
    }
  }

  if (skipped.length > 0) {
    console.log('Could not check these files, skipping them:');
    for (const s2 of skipped) console.log(`  ${s2}`);
    console.log('');
  }

  if (problems.length === 0) {
    console.log(fix ? 'Done.' : 'All changed lines are formatted.');
    return;
  }

  console.log('These lines were written by this change and are not formatted:\n');
  for (const { file, hits } of problems) {
    for (const [s, e] of hits) console.log(`  ${file}:${s}${e > s ? `-${e}` : ''}`);
  }
  const scope = staged ? '--staged' : bases.map((b) => `--base ${b}`).join(' ');
  console.log(
    '\nOnly those lines need fixing. The rest of each file is left alone:\n' +
      `  node scripts/prettier-check-changed.js ${scope} --fix \\\n` +
      problems.map((p) => `    ${p.file}`).join(' \\\n') +
      '\n'
  );
  process.exit(1);
}

main();
