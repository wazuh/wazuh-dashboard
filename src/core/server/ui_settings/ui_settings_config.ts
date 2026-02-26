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

import { get } from 'lodash';
import { unset } from '@osd/std';
import { schema, TypeOf } from '@osd/config-schema';
import { ConfigDeprecation, ConfigDeprecationProvider } from 'src/core/server';
import { ServiceConfigDescriptor } from '../internal_types';

const USE_NEW_HOME_PAGE_SETTING = 'home:useNewHomePage';

// Wazuh safeguard:
// If this key is forced from opensearch_dashboards.yml (uiSettings.overrides),
// we drop it to prevent startup failures and keep the feature disabled.
// To re-enable the setting in the future, remove this deprecation and also
// update the setting definition in src/plugins/home/server/ui_settings.ts.
const ignoreUseNewHomePageOverride: ConfigDeprecation = (settings, fromPath, log) => {
  const settingPath = `${fromPath}.overrides.${USE_NEW_HOME_PAGE_SETTING}`;
  if (get(settings, settingPath) === undefined) {
    return settings;
  }

  unset(settings, settingPath);
  log(
    `"${settingPath}" is ignored in Wazuh because the new home page is not supported and remains disabled`
  );
  return settings;
};

// Keep the custom deprecation in this list so startup config processing always
// strips `uiSettings.overrides.home:useNewHomePage` before validation/boot.
const deprecations: ConfigDeprecationProvider = ({ unused, renameFromRoot }) => [
  unused('enabled'),
  renameFromRoot('server.defaultRoute', 'uiSettings.overrides.defaultRoute'),
  // Keep this entry while new home page is intentionally disabled.
  ignoreUseNewHomePageOverride,
];

export const DEFAULT_THEME_VERSION = 'v7';

/* There are 4 levels of uiSettings:
 *   1) defaults hardcoded in code
 *   2) defaults provided in the opensearch_dashboards.yml
 *   3) values selected by the user and received from savedObjects
 *   4) overrides provided in the opensearch_dashboards.yml
 *
 * Each of these levels override the one above them.
 *
 * The schema below exposes only a limited set of settings to be set in the config file.
 *
 * The schema is temporarily relaxed to allow overriding the `darkMode` and setting
 * `defaults`. An upcoming change would relax them further to allow setting them.
 */

const configSchema = schema.object({
  overrides: schema.object({}, { unknowns: 'allow' }),
  defaults: schema.object({
    'theme:darkMode': schema.maybe(schema.boolean({ defaultValue: false })),
    'theme:version': schema.maybe(schema.string({ defaultValue: DEFAULT_THEME_VERSION })),
  }),
});

export type UiSettingsConfigType = TypeOf<typeof configSchema>;

export const config: ServiceConfigDescriptor<UiSettingsConfigType> = {
  path: 'uiSettings',
  schema: configSchema,
  deprecations,
};
