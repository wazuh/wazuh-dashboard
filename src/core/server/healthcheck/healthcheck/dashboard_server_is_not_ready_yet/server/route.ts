/* eslint-disable @osd/eslint/require-license-header */
import path from 'node:path';
import { HttpServerSetup } from 'opensearch-dashboards/server/http/http_server';
import { SERVER_NOT_READY_SCRIPT_ROUTE, SERVER_NOT_READY_STYLES_ROUTE } from './constants';

export const configureNotReadyRoutes = (server: HttpServerSetup['server']) => {
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
};
