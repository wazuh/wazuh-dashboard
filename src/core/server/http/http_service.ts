/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * The OpenSearch Contributors require contributions made to
 * this file be licensed under the Apache-2.0 license or a
 * compatible open source license.
 *
 * Any modifications Copyright OpenSearch Contributors. See
 * GitHub history for details.
 */

/*
 * Licensed to Elasticsearch B.V. under one or more contributor
 * license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright
 * ownership. Elasticsearch B.V. licenses this file to you under
 * the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

// Wazuh: socket type to track the NotReady server connections
import type { Socket } from 'net';
import { Observable, Subscription, combineLatest } from 'rxjs';
import { first, map } from 'rxjs/operators';
import { Server } from '@hapi/hapi';
import { pick } from '@osd/std';

import { CoreService } from '../../types';
import { Logger, LoggerFactory } from '../logging';
import { ContextSetup } from '../context';
import { Env, InternalDynamicConfigServiceStart } from '../config';
import { CoreContext } from '../core_context';
import { PluginOpaqueId } from '../plugins';
import { CspConfigType, config as cspConfig } from '../csp';
import { CspReportOnlyConfigType, config as cspReportOnlyConfig } from '../csp_report_only';

import { Router } from './router';
import { HttpConfig, HttpConfigType, config as httpConfig } from './http_config';
import { HttpServer } from './http_server';
import { HttpsRedirectServer } from './https_redirect_server';

import {
  RequestHandlerContextContainer,
  RequestHandlerContextProvider,
  InternalHttpServiceSetup,
  InternalHttpServiceStart,
} from './types';

import { BasePath, RequestHandlerContext } from '../../server';
import { registerCoreHandlers } from './lifecycle_handlers';

// Wazuh: time to wait for the NotReady server to stop before destroying its remaining sockets
const NOT_READY_SERVER_STOP_TIMEOUT_MS = 5000;

export interface SetupDeps {
  context: ContextSetup;
  // Wazuh
  enhanceNotReadyServer?: (server: Server, basePath: BasePath) => void;
}

export interface StartDeps {
  dynamicConfigService: InternalDynamicConfigServiceStart;
}

/** @internal */
export class HttpService
  implements CoreService<InternalHttpServiceSetup, InternalHttpServiceStart> {
  private readonly httpServer: HttpServer;
  private readonly httpsRedirectServer: HttpsRedirectServer;
  private readonly config$: Observable<HttpConfig>;
  private configSubscription?: Subscription;

  private readonly logger: LoggerFactory;
  private readonly log: Logger;
  private readonly env: Env;
  private notReadyServer?: Server;
  // Wazuh: in-flight stop of the NotReady server
  private notReadyServerStop?: Promise<void>;
  // Wazuh: raw sockets of the NotReady server, including those still in the TLS handshake
  private readonly notReadyServerSockets = new Set<Socket>();
  private internalSetup?: InternalHttpServiceSetup;
  private requestHandlerContext?: RequestHandlerContextContainer;

  constructor(private readonly coreContext: CoreContext) {
    const { logger, configService, env } = coreContext;

    this.logger = logger;
    this.env = env;
    this.log = logger.get('http');
    this.config$ = combineLatest([
      configService.atPath<HttpConfigType>(httpConfig.path),
      configService.atPath<CspConfigType>(cspConfig.path),
      configService.atPath<CspReportOnlyConfigType>(cspReportOnlyConfig.path),
    ]).pipe(map(([http, csp, cspReportOnly]) => new HttpConfig(http, csp, cspReportOnly)));
    this.httpServer = new HttpServer(logger, 'OpenSearchDashboards');
    this.httpsRedirectServer = new HttpsRedirectServer(logger.get('http', 'redirect', 'server'));
  }

  public async setup(deps: SetupDeps) {
    this.requestHandlerContext = deps.context.createContextContainer();
    this.configSubscription = this.config$.subscribe(() => {
      if (this.httpServer.isListening()) {
        // If the server is already running we can't make any config changes
        // to it, so we warn and don't allow the config to pass through.
        this.log.warn(
          'Received new HTTP config after server was started. Config will **not** be applied.'
        );
      }
    });

    const config = await this.config$.pipe(first()).toPromise();

    if (this.shouldListen(config)) {
      // Wazuh: inject dependencies
      await this.runNotReadyServer(config, deps);
    }

    const { registerRouter, ...serverContract } = await this.httpServer.setup(config);

    registerCoreHandlers(serverContract, config, this.env);

    this.internalSetup = {
      ...serverContract,

      createRouter: (path: string, pluginId: PluginOpaqueId = this.coreContext.coreId) => {
        const enhanceHandler = this.requestHandlerContext!.createHandler.bind(null, pluginId);
        const router = new Router(path, this.log, enhanceHandler);
        registerRouter(router);
        return router;
      },

      registerRouteHandlerContext: <T extends keyof RequestHandlerContext>(
        pluginOpaqueId: PluginOpaqueId,
        contextName: T,
        provider: RequestHandlerContextProvider<T>
      ) => this.requestHandlerContext!.registerContext(pluginOpaqueId, contextName, provider),
    };

    return this.internalSetup;
  }

  // this method exists because we need the start contract to create the `CoreStart` used to start
  // the `plugin` and `legacy` services.
  public getStartContract(): InternalHttpServiceStart {
    return {
      ...pick(this.internalSetup!, ['auth', 'basePath', 'getServerInfo']),
      isListening: () => this.httpServer.isListening(),
    };
  }

  public async start(deps: StartDeps) {
    const config = await this.config$.pipe(first()).toPromise();
    if (this.shouldListen(config)) {
      // Wazuh: shared with `stop()`, which can run concurrently on shutdown during startup
      await this.stopNotReadyServer();
      // If a redirect port is specified, we start an HTTP server at this port and
      // redirect all requests to the SSL port.
      if (config.ssl.enabled && config.ssl.redirectHttpFromPort !== undefined) {
        await this.httpsRedirectServer.start(config);
      }

      await this.httpServer.start(deps.dynamicConfigService);
    }

    return this.getStartContract();
  }

  /**
   * Indicates if http server has configured to start listening on a configured port.
   * We shouldn't start http service in two cases:
   * 1. If `server.autoListen` is explicitly set to `false`.
   * 2. When the process is run as dev cluster manager.
   * will fork a dedicated process where http service will be set up instead.
   * @internal
   * */
  private shouldListen(config: HttpConfig) {
    return !this.coreContext.env.isDevClusterManager && config.autoListen;
  }

  public async stop() {
    if (this.configSubscription === undefined) {
      return;
    }

    this.configSubscription.unsubscribe();
    this.configSubscription = undefined;

    // Wazuh: shared with `start()` to avoid stopping the hapi server twice
    await this.stopNotReadyServer();
    await this.httpServer.stop();
    await this.httpsRedirectServer.stop();
  }

  // Wazuh: hapi rejects `stop()` while a previous `stop()` is in progress, so the NotReady server is
  // stopped once and later callers wait for that same stop to finish.
  private async stopNotReadyServer() {
    if (this.notReadyServer) {
      this.log.debug('stopping NotReady server');
      const notReadyServer = this.notReadyServer;
      this.notReadyServer = undefined;
      // Wazuh: hapi only tracks sockets after the TLS handshake completes, so a socket stuck in the
      // handshake blocks the stop until Node's 120 s handshake timeout. Destroy every remaining
      // socket once the stop timeout elapses.
      const destroyTimer = setTimeout(() => {
        this.log.debug(`destroying ${this.notReadyServerSockets.size} NotReady server sockets`);
        this.notReadyServerSockets.forEach((socket) => socket.destroy());
      }, NOT_READY_SERVER_STOP_TIMEOUT_MS);
      this.notReadyServerStop = (async () => {
        try {
          await notReadyServer.stop({ timeout: NOT_READY_SERVER_STOP_TIMEOUT_MS });
        } finally {
          clearTimeout(destroyTimer);
          this.notReadyServerSockets.clear();
        }
      })();
    }
    await this.notReadyServerStop;
  }

  // Wazuh: inject dependencies
  private async runNotReadyServer(config: HttpConfig, deps: any) {
    this.log.debug('starting NotReady server');
    const httpServer = new HttpServer(this.logger, 'NotReady');
    const { server, basePath } = await httpServer.setup(config);
    this.notReadyServer = server;

    // Wazuh: decorate server
    deps.enhanceNotReadyServer?.(server, basePath);
    // use hapi server while OpenSearchDashboardsResponseFactory doesn't allow specifying custom headers
    // https://github.com/elastic/kibana/issues/33779
    // Wazuh: comment
    // this.notReadyServer.route({
    //   path: '/{p*}',
    //   method: '*',
    //   handler: (req, responseToolkit) => {
    //     this.log.debug(`Wazuh dashboard server is not ready yet ${req.method}:${req.url.href}.`);

    //     // If server is not ready yet, because plugins or core can perform
    //     // long running tasks (build assets, saved objects migrations etc.)
    //     // we should let client know that and ask to retry after 30 seconds.
    //     return responseToolkit
    //       .response('Wazuh dashboard server is not ready yet')
    //       .code(503)
    //       .header('Retry-After', '30');
    //   },
    // });
    // Wazuh: track raw sockets so the NotReady server stop can destroy them if it hangs
    this.notReadyServer.listener.on('connection', (socket: Socket) => {
      this.notReadyServerSockets.add(socket);
      socket.once('close', () => this.notReadyServerSockets.delete(socket));
    });
    await this.notReadyServer.start();
  }
}
