/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { PluginInitializerContext } from 'opensearch-dashboards/public';
import { AboutPlugin } from './plugin';

export const plugin = (initializerContext: PluginInitializerContext) =>
  new AboutPlugin(initializerContext);
