/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { PluginConfigDescriptor } from 'opensearch-dashboards/server';
import { configSchema, AboutConfigType } from './config';
import { AboutPlugin } from './plugin';

export const config: PluginConfigDescriptor<AboutConfigType> = {
  schema: configSchema,
  exposeToBrowser: {
    communityLinks: true,
  },
};

export function plugin() {
  return new AboutPlugin();
}
