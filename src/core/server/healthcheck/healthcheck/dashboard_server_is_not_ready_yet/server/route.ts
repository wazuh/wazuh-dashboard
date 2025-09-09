/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import path from 'node:path';
import { HttpServerSetup } from 'opensearch-dashboards/server/http/http_server';
import { Request, ResponseToolkit } from '@hapi/hapi';
import {
  SERVER_NOT_READY_RESET_STYLES_ROUTE,
  SERVER_NOT_READY_SCRIPT_ROUTE,
  SERVER_NOT_READY_STYLES_ROUTE,
} from './constants';
import { dashboardServerIsNotReadyYet } from '..';

export const configureDashboardServerIsNotReadyRoutes = (
  server: HttpServerSetup['server'],
  {
    documentationTroubleshootingLink,
    serverBasePath = '',
  }: { documentationTroubleshootingLink?: string; serverBasePath: string }
) => {
  const appName = 'Wazuh dashboard';

  server.route({
    path: '/{p*}',
    method: '*',
    handler: (_request: Request, h: ResponseToolkit) => {
      const html = `<!DOCTYPE html> ${dashboardServerIsNotReadyYet({
        appName,
        documentationTroubleshootingLink,
        serverBasePath,
      })}`;
      // If server is not ready yet, because plugins or core can perform
      // long running tasks (build assets, saved objects migrations etc.)
      // we should let client know that and ask to retry after 30 seconds.
      // Wazuh
      return h.response(html).type('text/html').code(503).header('Retry-After', '30').takeover();
    },
  });

  server.route({
    path: SERVER_NOT_READY_SCRIPT_ROUTE,
    method: 'get',
    handler: {
      file: path.join(__dirname, '../client/script.js'),
    },
  });

  server.route({
    path: SERVER_NOT_READY_STYLES_ROUTE,
    method: 'get',
    handler: {
      file: path.join(__dirname, '../client/styles.css'),
    },
  });

  server.route({
    path: SERVER_NOT_READY_RESET_STYLES_ROUTE,
    method: 'get',
    handler: {
      file: path.join(__dirname, '../client/reset.css'),
    },
  });
};
