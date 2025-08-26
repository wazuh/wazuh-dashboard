/* eslint-disable @osd/eslint/require-license-header */
// @ts-check

/**
 * @typedef {Object} Task
 * @property {string} name
 * @property {string} status
 * @property {string} result
 * @property {any} data
 * @property {string} createdAt
 * @property {string} startedAt
 * @property {string} finishedAt
 * @property {number} duration
 * @property {string} error
 * @property {Object} _meta
 * @property {boolean} _meta.isCritical
 * @property {boolean} _meta.isEnabled
 */

/**
 * @typedef {Object} HealthCheckTasks
 * @property {string} message
 * @property {Task[]} tasks
 */

/**
 * @typedef {Object} FetchOptions
 * @property {'GET' | 'POST' | 'PUT' | 'DELETE'} method
 * @property {any} [body]
 * @property {Record<string, string>} [headers]
 */

/** @type {Task[]} */
let tasks = [];
const FILENAME = 'healthcheck.json';

/**
 * Simple HTTP request wrapper
 */
class HttpService {
  /**
   * @private
   * @type {string}
   */
  baseUrl;

  constructor() {
    this.baseUrl = window.location.origin + window.__CONFIG.serverBasePath;
  }

  /**
   * @template T
   * @param {string} endpoint
   * @returns {Promise<T>}
   */
  get(endpoint) {
    return this.request('GET', endpoint);
  }

  /**
   * @template T
   * @param {string} endpoint
   * @param {any} [payload]
   * @returns {Promise<T>}
   */
  post(endpoint, payload) {
    return this.request('POST', endpoint, payload);
  }

  /**
   * @private
   * @param {string} endpoint
   * @param {FetchOptions} options
   */
  fetch(endpoint, options) {
    return fetch(this.baseUrl + endpoint, options);
  }

  /**
   * @template T
   * @private
   * @returns {Promise<T>}
   */
  async request(
    /** @type {'GET' | 'POST' | 'PUT' | 'DELETE'} */ method,
    /** @type {string} */ endpoint,
    /** @type {any} */ payload = undefined
  ) {
    /** @type {FetchOptions} */
    const options = { method, body: payload };

    if (payload) {
      options.headers = { 'content-type': 'application/json' };
    }

    const response = await this.fetch(endpoint, options);

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(
        `[HTTP ERROR] Status: ${response.status} - ${response.statusText}. Response: ${errorText}`
      );
    }

    return await response.json();
  }
}

const httpService = new HttpService();

class UseCases {
  static async getHealthCheckTasks() {
    try {
      const response = await /** @type {Promise<HealthCheckTasks>} */ (httpService.get(
        '/api/healthcheck/internal'
      ));
      return response.tasks;
    } catch (err) {
      console.error('Failed to get health check tasks:', err);
      return [];
    }
  }

  static async runHealthCheckByName() {
    const params = new URLSearchParams();
    params.set(
      'name',
      tasks
        .filter(({ error, _meta }) => _meta && _meta.isCritical && error)
        .map(({ name }) => name)
        .toString()
    );
    try {
      const response = await /** @type {Promise<HealthCheckTasks>} */ (httpService.post(
        `/api/healthcheck/internal?${params.toString()}`
      ));

      return combineTaskArraysByKey(tasks || [], response.tasks, 'name');
    } catch (err) {
      console.error('Failed to run health check:', err);
      return [];
    }
  }
}

/**
 * Combines two arrays of tasks by a specific key.
 * @param {Task[]} arr1
 * @param {Task[]} arr2
 * @param {keyof Task} key
 * @returns {Task[]}
 */
function combineTaskArraysByKey(arr1, arr2, key) {
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
function downloadHealthChecksAsJSONFile() {
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

// Run health checks data
async function runHealthCheck() {
  const btn = /** @type {HTMLButtonElement}  */ (document.getElementById(
    'btn-run-failed-critical-checks'
  ));
  btn.disabled = true;
  const healthCheckTasks = await UseCases.runHealthCheckByName();
  updateContent(healthCheckTasks);
  btn.disabled = false;
}

/**
 * Maps each element of an array using a mapper function.
 * @template T
 * @param {T[]} arr
 * @param {(item: T) => string} mapper
 * @returns {string}
 */
function map(arr, mapper) {
  if (!Array.isArray(arr) || typeof mapper !== 'function') {
    throw new Error('Invalid arguments');
  }
  const result = [];
  for (const item of arr) {
    result.push(mapper(item));
  }
  return result.join('');
}

/**
 * Returns trueValue if condition is true, otherwise falseValue.
 * @param {boolean} condition
 * @param {string} trueValue
 * @param {string} [falseValue]
 */
function when(condition, trueValue, falseValue = '') {
  return condition ? trueValue : falseValue;
}

/**
 * Function to update HTML content
 * @param {Task[]} data
 */
function updateContent(data) {
  tasks = data;
  const criticalTasks = data.filter(({ error, _meta }) => _meta && _meta.isCritical && error);

  const nonCriticalTasks = data.filter(
    ({ error, _meta }) => (!_meta || (_meta && !_meta?.isCritical)) && error
  );

  let content = '';
  if (criticalTasks.length > 0 || nonCriticalTasks.length > 0) {
    content += /* html */ `
      <div style="height:20px"></div>
      <div class="d-flex d-ai-center d-gap-m">
        <div>Some errors were found related to the health check</div>
        ${when(
          tasks && tasks.length > 0,
          /* html */ ` <button class="btn btn-export-checks" id="btn-export-checks" onclick="${downloadHealthChecksAsJSONFile.name}()">Export checks</button>`
        )}
      </div>
    `;
  }

  if (criticalTasks.length) {
    content += /* html */ `
      <div>
        <div>
          <span>There are some <span class="text-danger">critical errors</span> that require to be solved, ensure the problems are solved and run the failed critical checks: </span>
          <button class="btn btn-run-failed-critical-checks" id="btn-run-failed-critical-checks" onclick="${
            runHealthCheck.name
          }()">Run failed critical checks</button>
        </div>
        <div>
          ${map(criticalTasks, (task) => {
            return /* html */ `<p>Check [<span class="text-danger">${task.name}</span>]: ${task.error}</p>`;
          })}
        </div>
      </div>
    `;
  }

  if (nonCriticalTasks.length) {
    content += /* html */ `
      <div>
        <div>There are some <span class="text-warn">minor errors</span>. Some features could require to solve these problems to work:</div>
        <div>
          ${map(nonCriticalTasks, (task) => {
            return /* html */ `<p>Check [<span class="text-warn">${task.name}</span>]: ${task.error}</p>`;
          })}
        </div>
      </div>
    `;
  }
  content += /* html */ `<div>For more details, review the app logs.</div>`;
  const root = /** @type {HTMLDivElement} */ (document.getElementById('root'));
  // eslint-disable-next-line no-unsanitized/property
  root.innerHTML = content;
}

// Auto-call the function when the page loads
window.addEventListener('load', () => {
  UseCases.getHealthCheckTasks().then((tasks) => updateContent(tasks));
});
