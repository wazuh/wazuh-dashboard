/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */
import { Observable } from 'rxjs';
import { first } from 'rxjs/operators';
import { CoreService } from '../../../types';
import { CoreContext } from '../../core_context';
import { Logger } from '../../logging';
import { HealthCheckServiceSetup, HealthCheckServiceStart } from './types';
import { HealthCheck } from './health_check';
import { HealthCheckConfigType } from './config';
import { addRoutesNotReadyServer } from './routes';

function createSetup(ctx: HealthCheckService): HealthCheckServiceSetup {
  return {
    register: ctx.healthCheck.register.bind(ctx.healthCheck),
    get: ctx.healthCheck.get.bind(ctx.healthCheck),
    getAll: ctx.healthCheck.getAll.bind(ctx.healthCheck),
  };
}

export class HealthCheckService
  implements CoreService<HealthCheckServiceSetup, HealthCheckServiceStart> {
  private readonly logger: Logger;
  healthCheck: HealthCheck;
  private readonly config$: Observable<HealthCheckConfigType>;

  constructor(private readonly coreContext: CoreContext) {
    this.logger = coreContext.logger.get('healthcheck');
    this.config$ = coreContext.configService.atPath<HealthCheckConfigType>('healthcheck');
    this.healthCheck = new HealthCheck(this.logger, {});
  }

  async setup(...params: any[]) {
    this.logger.debug('Setup starts');
    const config = await this.config$.pipe(first()).toPromise();

    await this.healthCheck.setup(params[0], config);

    this.logger.debug('Setup finished');
    return createSetup(this);
  }

  async start(...params: any[]) {
    this.logger.debug('Start starts');
    await this.healthCheck.start(...params);

    this.logger.debug('Start finished');
    return createSetup(this);
  }

  stop(): void | Promise<void> {
    this.logger.debug('Stop starts');
    this.healthCheck.stop();
    this.logger.debug('Stop finished');
  }

  enhanceNotReadyServer(server, basePath) {
    const appName = 'Wazuh dashboard';

    addRoutesNotReadyServer(server, { healthcheck: this.healthCheck, logger: this.logger });

    server.route({
      path: '/{p*}',
      method: '*',
      handler: (request, h) => {
        const html = /* html */ `
          <!DOCTYPE html>
          <html>
            <head>
              <title>${appName}</title>
            </head>
            <style>
              .text-danger{color:red;}
              .text-warn{color:#FF8C00;}
              .btn {
                background-color: transparent;
                color: #e57373; /* Light red */
                border: 2px solid #e57373;
                padding: 10px 20px;
                font-size: 16px;
                border-radius: 4px;
                cursor: pointer;
                transition: background-color 0.3s ease, color 0.3s ease;
              }
              .btn:disabled,
              .btn[disabled] {
                cursor: not-allowed;
                opacity: 0.7;
              }

              .btn-run-failed-critical-checks{
                color: #e57373; /* Light red */
                border: 2px solid #e57373;
              }
              .btn-run-failed-critical-checks:hover{
                background-color: #e57373;
                color: white;
              }
              .btn-run-failed-critical-checks:disabled,
              .btn-run-failed-critical-checks[disabled]{
                background-color: #f8d7da;   /* Light red background */
                color: #a1a1a1;              /* Muted text color */
                border: 2px solid #f5c2c7;   /* Soft border */
              }

              .btn-export-checks{
                color: #3595F9; /* Light red */
                border: 2px solid #3595F9;
              }
              .btn-export-checks:hover{
                background-color: #3595F9;
                color: white;
              }
              .btn-export-checks:disabled,
              .btn-export-checks[disabled]{
                background-color: #f8d7da;   /* Light red background */
                color: #a1a1a1;              /* Muted text color */
                border: 2px solid #f5c2c7;   /* Soft border */
              }
            </style>

            <script>
              let tasks;

              // Merge arrays
              function mergeArraysByKey(arr1, arr2, key) {
                const map = new Map();

                [...arr1, ...arr2].forEach(item => {
                  map.set(item[key], item); // Later items overwrite earlier ones
                });

                return Array.from(map.values());
              }

              // Download file
              function downloadChecksFile() {
                const btn = document.getElementById('btn-export-checks');
                try{
                  btn.disabled = true;
                  const filename ='healthcheck.json'
                  const mimeType = 'application/json'
                  const content = JSON.stringify({checks: tasks, _meta: {server: 'not-ready'}}, null, 2);
                  // Normalize content into a Blob
                  let blob;
                  if (content instanceof Blob) {
                    blob = content;
                  } else if (content instanceof Uint8Array) {
                    blob = new Blob([content], { type: mimeType });
                  } else {
                    blob = new Blob([String(content)], { type: mimeType });
                  }

                  // Create an object URL and anchor element
                  const url = URL.createObjectURL(blob);
                  const link = document.createElement('a');
                  link.href = url;
                  link.download = filename;

                  // Append, click, and clean up
                  document.body.appendChild(link);
                  link.click();
                  document.body.removeChild(link);
                  URL.revokeObjectURL(url);
                }catch(error){
                  console.error(error);
                }finally{
                  btn.disabled = false;
                }

              }

              // http client wrapper
              async function httpClient(endpoint, method, payload){
                const baseUrl = window.location.origin + '${
                  basePath.serverBasePath || ''
                }'; // Automatically detects base URL injecting the basePath

                const options = {
                  method: method || 'GET',
                  body: payload || undefined,
                }

                if(payload){
                  options.headers= {
                    'content-type': 'application/json'
                  }
                }
                const response = await fetch(baseUrl + endpoint, options);

                if (!response.ok) {
                  throw new Error('HTTP error! status: ' + response.status);
                }

                return await response.json()
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
                const btn = document.getElementById('btn-run-failed-critical-checks');
                try {
                  btn.disabled = true;
                  const params = new URLSearchParams;
                  params.set('name', tasks.filter(({ error, _meta }) => _meta && _meta.isCritical && error).map(({name}) => name));
                  const data = await httpClient('/api/healthcheck/internal?'+params.toString(), 'POST');
                  updateContent(mergeArraysByKey(tasks || [], data.tasks, 'name'));
                } catch (error) {
                  console.error('Failed to fetch health check:', error);
                }finally{
                  btn.disabled = false;
                }
              }

              // Function to update HTML content
              function updateContent(data) {
                tasks = data;
                const div = document.getElementById('root');

                const criticalErrors = data.filter(({ error, _meta }) => _meta && _meta.isCritical && error);

                const nonCriticalErrors = data.filter(({ error, _meta }) => (!_meta || (_meta && !_meta?.isCritical)) && error);

                let content = '';
                if(criticalErrors.length > 0  || nonCriticalErrors.length > 0){
                  content += '<p>'
                  content += '  <span>Health check<span>'

                  if(tasks && tasks.length > 0){
                    content += ' <button class="btn btn-export-checks" id="btn-export-checks" onclick="downloadChecksFile()">Export checks</button>'
                  }

                  content += '</p>'
                }

                if(criticalErrors.length){
                  content += '<div>'
                  content += '  <div><span>There are some <span class="text-danger">critical errors</span> that require to be solved, ensure the problems are solved and run the failed critical checks: </span><button class="btn btn-run-failed-critical-checks" id="btn-run-failed-critical-checks" onclick="runHealthCheck()">Run failed critical checks</button></div>'
                  content += '  <div>'
                  criticalErrors.forEach(task => {
                    content += [
                      '<p>Check [<span class="text-danger">',
                      task.name,
                      '</span>]: ',
                      task.error,
                      '</p>'
                      ].join('');
                  });
                  content += '  </div>'
                  content += '</div>'
                }

                if(nonCriticalErrors.length){
                  content += '<div>'
                  content += '  <div>There are some <span class="text-warn">minor errors</span>. Some features could require to solve these problems to work:</div>'
                  content += '  <div>'
                  nonCriticalErrors.forEach(task => {
                    content += [
                      '<p>Check [<span class="text-warn">',
                      task.name,
                      '</span>]: ',
                      task.error,
                      '</p>'
                      ].join('');
                  });
                  content += '  </div>'
                  content += '</div>'
                }
                content += '<div>For more details, review the app logs.</div>'
                div.innerHTML = content;
              }

              // Auto-call the function when the page loads
              window.addEventListener('load', fetchHealthCheck);
            </script>
            <body>
              <p>${appName} server is not ready yet</>
              <div id="root"></div>
            </body>
          </html>
        `;
        // If server is not ready yet, because plugins or core can perform
        // long running tasks (build assets, saved objects migrations etc.)
        // we should let client know that and ask to retry after 30 seconds.
        // Wazuh
        return h.response(html).type('text/html').code(503).header('Retry-After', '30').takeover();
      },
    });
  }
}
