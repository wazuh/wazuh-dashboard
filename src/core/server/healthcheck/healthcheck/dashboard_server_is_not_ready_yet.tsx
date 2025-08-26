import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

interface NotReadyServerProps {
  appName: string;
  documentationTroubleshootingLink?: string;
  serverBasePath: string;
}

const DashboardServerIsNotReadyYetComponent = ({
  appName,
  documentationTroubleshootingLink,
  serverBasePath,
}: NotReadyServerProps) => {
  return (
    <html lang="en">
      <head>
        <title>{appName}</title>
      </head>
      <style
        // eslint-disable-next-line react/no-danger
        dangerouslySetInnerHTML={{
          __html: /* css */ `
              .text-danger{color:red;}
              .text-warn{color:#FF8C00;}
              .btn {
                background-color: transparent;
                color: #e57373; /* Light red */
                border: 2px solid #e57373;
                padding: 5px 10px;
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

              pre.code, code.code {
                background-color: #f5f5f5; /* light gray */
                color: #333;               /* dark text for contrast */
                font-family: Consolas, Monaco, 'Courier New', monospace;
                font-size: 14px;
                padding: 10px;
                border-radius: 5px;
                overflow-x: auto;
                display: block;
                white-space: pre-wrap;
              }

              .d-flex{
                display: flex;
              }

              .d-jc-center{
                justify-content: center;
              }

              .d-ai-center{
                align-items: center;
              }

              .d-gap-m{
                gap: 10px;
              }

              .margin-m{
                margin: 10px;
              }

              .padding-m{
                padding: 10px;
              }
        `,
        }}
      />
      <script
        // eslint-disable-next-line react/no-danger
        dangerouslySetInnerHTML={{
          __html: /* javascript */ `
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
                const baseUrl = window.location.origin + '${serverBasePath}'; // Automatically detects base URL injecting the basePath

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
                  console.error('Failed to run health check:', error);
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
                  content += '<div style="height:20px"></div>'
                  content += '<div class="d-flex d-ai-center d-gap-m">'
                  content += '  <div>Some errors were found related to the health check</div>'

                  if(tasks && tasks.length > 0){
                    content += ' <button class="btn btn-export-checks" id="btn-export-checks" onclick="downloadChecksFile()">Export checks</button>'
                  }

                  content += '</div>'
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

              // Copy debug command
              function fallbackCopyText(text) {
                var textarea = document.createElement('textarea');
                textarea.value = text;

                // Prevent scrolling to bottom
                textarea.setAttribute('readonly', '');
                textarea.style.position = 'absolute';
                textarea.style.left = '-9999px';
                document.body.appendChild(textarea);

                textarea.select();
                textarea.setSelectionRange(0, textarea.value.length);

                try {
                  document.execCommand('copy');
                  console.log('Copied to clipboard via execCommand!');
                } catch (err) {
                  console.error('Fallback: Oops, unable to copy', err);
                }

                document.body.removeChild(textarea);
              }

              // Auto-call the function when the page loads
              window.addEventListener('load', fetchHealthCheck);
              //# sourceURL=main.js
        `,
        }}
      />
      <body>
        <p>{appName} server is not ready yet</p>
        <p>
          If this message persists after a time of the initialization, this could be caused for some
          problem. Review the app logs for more information.
        </p>
        {documentationTroubleshootingLink ? (
          <div>
            <a rel="noopener noreferrer" target="_blank" href={documentationTroubleshootingLink}>
              Troubleshooting
            </a>
          </div>
        ) : (
          <></>
        )}
        <div id="root" />
      </body>
    </html>
  );
};

export const dashboardServerIsNotReadyYet = (props: NotReadyServerProps) =>
  renderToStaticMarkup(DashboardServerIsNotReadyYetComponent(props));
