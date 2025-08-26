/* eslint-disable @osd/eslint/require-license-header */
// @ts-check

/**
 * @typedef {Object} Task
 * @property {string} name
 * @property {boolean} error
 * @property {Object} _meta
 * @property {boolean} _meta.isCritical
 */

/** @type {Task[]} */
let tasks = [];
const FILENAME = 'healthcheck.json';

// Merge arrays
function mergeArraysByKey(
  /** @type {Task[]}  */ arr1,
  /** @type {Task[]}  */ arr2,
  /** @type {keyof Task}  */ key
) {
  if (!Array.isArray(arr1)) arr1 = [];
  if (!Array.isArray(arr2)) arr2 = [];

  const isPlainObject = (/** @type {unknown}  */ v) =>
    v && typeof v === 'object' && v.constructor === Object;

  /** @type {Map<string, Task>} */
  const map = new Map();

  // Seed with arr1 (preserve insertion order)
  arr1.forEach((item) => {
    if (!item) return;
    const k = item[key];
    if (k === undefined) return;
    map.set(String(k), item);
  });

  // Merge/overwrite with arr2. If both values are plain objects, shallow-merge them.
  arr2.forEach((item) => {
    if (!item) return;
    const k = item[key];
    if (k === undefined) return;
    const mapKey = String(k);

    if (map.has(mapKey)) {
      const existing = map.get(mapKey);
      if (isPlainObject(existing) && isPlainObject(item)) {
        map.set(mapKey, { ...existing, ...item });
      } else {
        map.set(mapKey, item);
      }
    } else {
      map.set(mapKey, item);
    }
  });

  return Array.from(map.values());
}

/**
 * Download the health checks as a JSON file
 */
function DownloadHealthChecksAsJSONFile() {
  const btn = /** @type {HTMLButtonElement} */ (document.getElementById('btn-export-checks'));
  try {
    btn.disabled = true;
    const content = JSON.stringify({ checks: tasks, _meta: { server: 'not-ready' } }, null, 2);
    // Normalize content into a Blob
    const blob = new Blob([String(content)], { type: 'application/json' });

    // Create an object URL and anchor element
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = FILENAME;

    // Append, click, and clean up
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  } catch (error) {
    console.error(error);
  } finally {
    btn.disabled = false;
  }
}

// http client wrapper
async function httpClient(
  /** @type {string} */ endpoint,
  /** @type {'GET' | 'POST' | 'PUT' | 'DELETE'} */ method = 'GET',
  /** @type {any} */ payload = undefined
) {
  const baseUrl = window.location.origin + window.__CONFIG.serverBasePath; // Automatically detects base URL injecting the basePath

  const options = { method, body: payload };

  if (payload) {
    options.headers = { 'content-type': 'application/json' };
  }
  const response = await fetch(baseUrl + endpoint, options);

  if (!response.ok) {
    throw new Error('HTTP error! status: ' + response.status);
  }

  return await response.json();
}

// Fetch health checks data
async function fetchHealthCheck() {
  try {
    const data = await httpClient('/api/healthcheck/internal');
    updateContent(data.tasks);
  } catch (error) {
    console.error('Failed to fetch health check:', error);
  }
}

// Run health checks data
async function runHealthCheck() {
  const btn = /** @type {HTMLButtonElement}  */ (document.getElementById(
    'btn-run-failed-critical-checks'
  ));
  try {
    btn.disabled = true;
    const params = new URLSearchParams();
    params.set(
      'name',
      tasks
        .filter(({ error, _meta }) => _meta && _meta.isCritical && error)
        .map(({ name }) => name)
        .toString()
    );
    const data = await httpClient('/api/healthcheck/internal?' + params.toString(), 'POST');
    updateContent(mergeArraysByKey(tasks || [], data.tasks, 'name'));
  } catch (error) {
    console.error('Failed to run health check:', error);
  } finally {
    btn.disabled = false;
  }
}

// Function to update HTML content
function updateContent(data) {
  tasks = data;
  const criticalErrors = data.filter(({ error, _meta }) => _meta && _meta.isCritical && error);

  const nonCriticalErrors = data.filter(
    ({ error, _meta }) => (!_meta || (_meta && !_meta?.isCritical)) && error
  );

  let content = '';
  if (criticalErrors.length > 0 || nonCriticalErrors.length > 0) {
    content += '<div style="height:20px"></div>';
    content += '<div class="d-flex d-ai-center d-gap-m">';
    content += '  <div>Some errors were found related to the health check</div>';

    if (tasks && tasks.length > 0) {
      content += ` <button class="btn btn-export-checks" id="btn-export-checks" onclick="${DownloadHealthChecksAsJSONFile.name}()">Export checks</button>`;
    }

    content += '</div>';
  }

  if (criticalErrors.length) {
    content += '<div>';
    content += `   <div><span>There are some <span class="text-danger">critical errors</span> that require to be solved, ensure the problems are solved and run the failed critical checks: </span><button class="btn btn-run-failed-critical-checks" id="btn-run-failed-critical-checks" onclick="${runHealthCheck.name}()">Run failed critical checks</button></div>`;
    content += '  <div>';
    criticalErrors.forEach((task) => {
      content += [
        '<p>Check [<span class="text-danger">',
        task.name,
        '</span>]: ',
        task.error,
        '</p>',
      ].join('');
    });
    content += '  </div>';
    content += '</div>';
  }

  if (nonCriticalErrors.length) {
    content += '<div>';
    content +=
      '  <div>There are some <span class="text-warn">minor errors</span>. Some features could require to solve these problems to work:</div>';
    content += '  <div>';
    nonCriticalErrors.forEach((task) => {
      content += [
        '<p>Check [<span class="text-warn">',
        task.name,
        '</span>]: ',
        task.error,
        '</p>',
      ].join('');
    });
    content += '  </div>';
    content += '</div>';
  }
  content += '<div>For more details, review the app logs.</div>';
  const root = /** @type {HTMLDivElement} */ (document.getElementById('root'));
  // eslint-disable-next-line no-unsanitized/property
  root.innerHTML = content;
}

// Auto-call the function when the page loads
window.addEventListener('load', fetchHealthCheck);
