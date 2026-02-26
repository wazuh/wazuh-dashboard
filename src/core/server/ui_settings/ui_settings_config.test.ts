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

import { applyDeprecations, configDeprecationFactory } from '@osd/config';
import { config } from './ui_settings_config';

const DEFAULT_CONFIG_PATH = 'uiSettings';

const applyUiSettingsDeprecations = (settings: Record<string, any> = {}) => {
  const deprecations = config.deprecations!(configDeprecationFactory);
  const deprecationMessages: string[] = [];
  const wrappedConfig: Record<string, any> = {
    [DEFAULT_CONFIG_PATH]: settings,
  };

  const migrated = applyDeprecations(
    wrappedConfig,
    deprecations.map((deprecation) => ({
      deprecation,
      path: DEFAULT_CONFIG_PATH,
    })),
    (msg) => deprecationMessages.push(msg)
  );

  return {
    messages: deprecationMessages,
    migrated,
  };
};

describe('uiSettings deprecations', () => {
  it('removes home:useNewHomePage from overrides and keeps other overrides', () => {
    const { migrated, messages } = applyUiSettingsDeprecations({
      overrides: {
        'home:useNewHomePage': true,
        'theme:version': 'v7',
      },
    });

    expect(messages).toMatchInlineSnapshot(`
      Array [
        "\\"uiSettings.overrides.home:useNewHomePage\\" is ignored in Wazuh because the new home page is not supported and remains disabled",
      ]
    `);
    expect(migrated.uiSettings.overrides).toEqual({
      'theme:version': 'v7',
    });
  });

  it('does not log anything when home:useNewHomePage is not overridden', () => {
    const { migrated, messages } = applyUiSettingsDeprecations({
      overrides: {
        'theme:darkMode': false,
      },
    });

    expect(messages).toEqual([]);
    expect(migrated.uiSettings.overrides).toEqual({
      'theme:darkMode': false,
    });
  });
});
