/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
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
        "\\"uiSettings.overrides.home:useNewHomePage\\" is ignored because the new home page is not supported and remains disabled",
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
