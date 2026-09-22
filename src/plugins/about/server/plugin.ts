/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import { CoreSetup, Plugin } from 'opensearch-dashboards/server';
import { defineRoutes } from './routes';

export class AboutPlugin implements Plugin {
  public setup(core: CoreSetup) {
    const router = core.http.createRouter();
    defineRoutes(router);
  }

  public start() {}

  public stop() {}
}
