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

  enhanceNotReadyServer(server) {
    const appName = 'Wazuh dashboard';

    server.route({
      path: '/{p*}',
      method: '*',
      handler: (request, h) => {
        let initializationTasksErrors;
        try {
          initializationTasksErrors = this.healthCheck
            .getChecksInfo()
            .filter(({ error }) => error)
            .map(({ error, name }) => `Check [${name}]: ${error}`);
          // eslint-disable-next-line no-empty
        } catch {}

        if (initializationTasksErrors?.length > 0) {
          const html = `
            <!DOCTYPE html>
            <html>
              <head>
                <title>${appName} - health check</title>
              </head>
              <body>
                <p>${appName} server is not ready yet</>
                <p>Health check</p>
                ${
                  initializationTasksErrors?.length
                    ? `
                      <div>
                        <div>There are some errors that require to be solved.</div>
                        <div>
                          ${(initializationTasksErrors as string[])
                            .map((error: string) => `<p>${error}</p>`)
                            .join('\n')}
                        </div>
                        <div>For more details, review the app logs.</div>
                      </div>`
                    : ''
                }
              </body>
            </html>
          `;
          // If server is not ready yet, because plugins or core can perform
          // long running tasks (build assets, saved objects migrations etc.)
          // we should let client know that and ask to retry after 30 seconds.
          // Wazuh
          return h
            .response(html)
            .type('text/html')
            .code(503)
            .header('Retry-After', '30')
            .takeover();
        }
        return h.continue;
      },
    });
  }
}
