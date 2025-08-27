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
 * @property {boolean} [_meta.isCritical]
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
  /** @private */
  static INTERNAL_HEALTHCHECK_API_ENDPOINT = '/api/healthcheck/internal';

  static async retrieveHealthCheckTasks() {
    try {
      const response = await /** @type {Promise<HealthCheckTasks>} */ (httpService.get(
        this.INTERNAL_HEALTHCHECK_API_ENDPOINT
      ));
      return response.tasks;
    } catch (err) {
      console.error('Failed to get health check tasks:', err);
      return [];
    }
  }

  static async executeHealthCheckForCriticalTasks() {
    const params = new URLSearchParams();
    params.set(
      'name',
      getCriticalTasks(tasks)
        .map(({ name }) => name)
        .toString()
    );
    try {
      const response = await /** @type {Promise<HealthCheckTasks>} */ (httpService.post(
        `${this.INTERNAL_HEALTHCHECK_API_ENDPOINT}?${params.toString()}`
      ));

      return combineTaskArraysByKey(tasks || [], response.tasks, 'name');
    } catch (err) {
      console.error('Failed to run health check:', err);
      return [];
    }
  }
}

class HealthCheckDocument {
  static ROOT_ID = 'healthcheck-root';
  static BTN_EXPORT_ID = 'btn-export';
  static BTN_RUN_FAILED_CRITICAL_CHECKS_ID = 'btn-run-failed-critical-checks';

  /**
   * @template {HTMLElement} T
   * @param {string} id
   * @returns {T}
   * @private
   */
  static getElementById(id) {
    return /** @type {T} */ (document.getElementById(id));
  }

  static getRoot() {
    return /** @type {HTMLDivElement} */ (this.getElementById(this.ROOT_ID));
  }

  /**
   * Sets the content of the root element.
   * @param {string} content
   */
  static setRootContent(content) {
    const root = this.getRoot();
    if (root) {
      // eslint-disable-next-line no-unsanitized/property
      root.innerHTML = content;
    }
  }

  static getExportButton() {
    return /** @type {HTMLButtonElement} */ (this.getElementById(this.BTN_EXPORT_ID));
  }

  static getRunFailedCriticalChecksButton() {
    return /** @type {HTMLButtonElement}  */ (this.getElementById(
      this.BTN_RUN_FAILED_CRITICAL_CHECKS_ID
    ));
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
  const btn = HealthCheckDocument.getExportButton();
  try {
    btn.disabled = true;
    const content = JSON.stringify({ checks: tasks, _meta: { server: 'not-ready' } });
    // Normalize content into a Blob
    const blob = new Blob([content], { type: 'application/json' });

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
  const btn = HealthCheckDocument.getRunFailedCriticalChecksButton();
  btn.disabled = true;
  const healthCheckTasks = await UseCases.executeHealthCheckForCriticalTasks();
  renderHealthCheckSummary(healthCheckTasks);
  btn.disabled = false;
}

/**
 * Maps each element of an array using a mapper function.
 * @template T
 * @param {T[]} arr
 * @param {(item: T) => string} mapper
 * @returns {string}
 */
function $map(arr, mapper) {
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
function $if(condition, trueValue, falseValue = '') {
  return condition ? trueValue : falseValue;
}

function filterErrorTasks() {
  /**
   *
   * @param {Task[]} tasks
   * @returns
   */
  return (tasks) => tasks.filter((task) => task.error);
}

/**
 *
 * @param {Task[]} tasks
 * @returns
 */
function getCriticalTasks(tasks) {
  return tasks.filter(filterErrorTasks).filter((task) => task._meta.isCritical);
}

/**
 *
 * @param {Task[]} tasks
 * @returns
 */
function getNonCriticalTasks(tasks) {
  return tasks.filter(filterErrorTasks).filter((task) => !task._meta || !task._meta?.isCritical);
}

class Icons {
  static healthCheck() {
    return /* html */ `
      <picture>
        <img
          width="52"
          src="data:image/png;base64,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"
          alt="Health Check Icon"
        />
      </picture>
    `;
  }

  static export() {
    return /* html */ `
      <picture>
        <img
          width="22"
          src="data:image/png;base64,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"
          alt="Export Icon"
        />
      </picture>
    `;
  }

  static wrench() {
    return /* html */ `
    <picture>
      <img
        width="52"
        src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFIAAABaCAYAAAArfwH2AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAPiSURBVHhe7Zy9axRBGMZX/wlzdmKvcodgqSlUuKjYWihCImppYach2llYqiQB0cJW/DgwFtFSkAS1F7uc/hW6T24WJ5M97+t53znD84OQuUB2dn/7vLMzc5fs+11SiInZH76LCZFIEhJJQiJJSCQJiSQhkSQkkoREkpBIEhJJQiJJSCQJiSQhkSQkkoREkpBIEhJJYmpEvu28C63BbGx+Ca3pIavIre7PYmX1WXH8xGwp8n346WBWVp8X5y9e2v7daSGbSEi4UMpYHlNGt7wJ+N1pEeouEim8fvPW2AJTYqE4di5cRWJsQwotxjgIxQ3KlU43kXiY4EItgcw3nbUsMl1EIoFL9x+EVz1azWPbX5PSaMzsOE5V6t4yzUVCYppEXPiTRw/Dq8k4WIq8e+d2cW3+SvhJDyTTc5pkLjJN4lz7LE1iBWS222d2yEQy074tMRWJ8sIFVSCJi2V6LIDMhVJkWuZeMs1EYiqSTnFQgtakfaC8PUrcTCRWHzFIIlJjDfqIU49UjrJqGhczkfHaGeWGsdEL9BWX+H+byHQDYq59OrT8aDWPhlYvldYyTURubH4LrR7NKB1e4CkeY13eRiL/3n2U2LBjY/VgGPQ1zJoafXqWt8lnyLEtVoG5HaYldWCiPukFQla/eSmmX/HM4fOn9dDiQ09kzh2YQVieG11kPAEHjcaB0PIn7Ts9Nyb00kapxmtrzOn6TX0Y4xY2LfqNwZg9xCubVy9fmM1l6SJRPthzrPiXSGs8RZo8tWO63V+h5Y9n33SRuOMot4qNza+h5c9WItIqjcAkkfEJ53yKxyss6+HFRKT38qyOdJnaah4JLRtMRHovz+pI+7ReppqVdrw8Qzo8U4m+4v5GWaaOi4lIsDB/ObR6pPuTlqR9pedigZlIpCDdNEjHLQvq0hifhxVmIkGahOUyKfFFssGx03csPdIITEUiCXXv7FnIrJOIvj3SCExFAjzB44uxkIm5at175/227yxw+Z8WuNB7NfIwSUbpjftExXE7nbVd71ZiZfW6XFd74vbPQarU7N5mmynOlakdNT3ppm1FDonATSTolyCAUhz2Exi4IXVDAxJu9QGEQZiPkTEoYSQPFxtvbEwKjoVj5pIIXEVWIDlIH+OJWpVyrj3PiiwiAWvJZr30G5ZsIvcaEklCIklIJAmJJCGRJCSShESSkEgSEklCIkm4bqPtZZRIEhJJImtpL33gfJRl8ZT/n5+kZBU5+/Rx8fHH9/BqPE4eOlysX70RXuVDpU1CIklo+kNCiSQhkSQkkoREkpBIEhJJQiJJSCQJiSQhkSQkkoREkpBICkXxB/8+yoZ/03zeAAAAAElFTkSuQmCC"
        alt="Wrench Icon"
      />
    </picture>
    `;
  }
}

class Components {
  /**
   *
   * @param {{
   *  children: string
   * }} param0
   * @returns
   */
  static card({ children }) {
    return /* html */ `
      <div class="card">
        <div class="card-body">
          ${children}
        </div>
      </div>
    `;
  }

  /**
   *
   * @param {{
   *  id: string,
   *  text: string,
   *  onclick?: string,
   *  icon?: string,
   *  iconPosition?: 'left' | 'right',
   * }} param0
   * @returns
   */
  static button({ id, text, onclick, icon = '', iconPosition = 'right' }) {
    return /* html */ `
      <button class="button" id="${id}" ${onclick ? `onclick="${onclick}()"` : ''}>
        ${$if(iconPosition === 'left', icon)}
        ${text}
        ${$if(iconPosition === 'right', icon)}
      </button>
    `;
  }

  /**
   * Render a health check item
   * @param {Task} task
   * @returns
   */
  static checkCriticalItem(task) {
    return /* html */ `<p style="font-weight: bold;">Check [<span style="color: var(--red);">${task.name}</span>]: ${task.error}</p>`;
  }

  /**
   *
   * @param {Task[]} tasks
   * @returns
   */
  static tableNonCriticalItems(tasks) {
    return /* html */ `
      <table>
        <thead>
          <tr style="text-align: left;">
            <th>Minor Error</th>
            <th>Details</th>
          </tr>
        </thead>
        <tbody>
          ${$map(
            tasks,
            (task) => /* html */ `
            <tr>
              <td>Check [<p style="color: var(--yellow); font-weight: 600;">${task.name}</p>]</td>
              <td>${task.error}</td>
            </tr>
          `
          )}
        </tbody>
      </table>
    `;
  }
}

/**
 *
 * @param {Task[]} criticalTasks
 * @param {Task[]} nonCriticalTasks
 * @returns
 */
function buildHealthCheckReport(criticalTasks, nonCriticalTasks) {
  return /* html */ `
    ${$if(
      criticalTasks.length > 0 || nonCriticalTasks.length > 0,
      /* html */ `
      ${Components.card({
        children: /* html */ `
          <div style="display: flex; align-items: center; gap: 0.25rem;">
            ${Icons.healthCheck()}
            <div class="healthcheck-title">
              Health Check
            </div>
          </div>
          ${$if(
            tasks && tasks.length > 0,
            Components.button({
              id: HealthCheckDocument.BTN_EXPORT_ID,
              text: 'Export checks',
              onclick: downloadHealthChecksAsJSONFile.name,
              icon: Icons.export(),
            })
          )}
        `,
      })}
      `
    )}

    ${$if(
      criticalTasks.length > 0,
      /* html */ `${Components.card({
        children: /* html */ `
        <div style="display: flex; gap: 0.25rem;">
          ${Icons.wrench()}
          <div>There are some <b>critical errors that require to be solved</b>,<br /> ensure the problems are solved and run the failed critical checks:</div>
        </div>
        ${Components.button({
          id: HealthCheckDocument.BTN_RUN_FAILED_CRITICAL_CHECKS_ID,
          text: 'Run failed critical checks',
          onclick: runHealthCheck.name,
        })}
      `,
      })}
      `
    )}

    ${$if(
      criticalTasks.length > 0 || nonCriticalTasks.length > 0,
      /* html */ `
      ${Components.card({
        children: /* html */ `
          <div>
            ${$map(criticalTasks, (task) => Components.checkCriticalItem(task))}
            <div>There are some <span style="color: var(--yellow); font-weight: 600;">minor errors</span>. Some features could require to solve these problems to work:</div>
            ${Components.tableNonCriticalItems(nonCriticalTasks)}
          </div>
        `,
      })}
      `
    )}
  `;
}

/**
 * Function to update HTML content
 * @param {Task[]} data
 */
function renderHealthCheckSummary(data) {
  tasks = data;
  const criticalTasks = getCriticalTasks(tasks);
  const nonCriticalTasks = getNonCriticalTasks(tasks);
  const content = buildHealthCheckReport(criticalTasks, nonCriticalTasks);
  HealthCheckDocument.setRootContent(content);
}

// Auto-call the function when the page loads
window.addEventListener('load', () => {
  UseCases.retrieveHealthCheckTasks().then((tasks) => renderHealthCheckSummary(tasks));
});
