/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import { schema } from '@osd/config-schema';
import { i18n } from '@osd/i18n';
// Wazuh: UiSettingScope is not used while the scope below is commented out
// import { UiSettingScope, UiSettingsParams } from '../types';
import { UiSettingsParams } from '../types';
import { ENABLE_AI_FEATURES } from '../../../../core/utils/constants';

export const getAIFeaturesSetting = (): Record<string, UiSettingsParams> => {
  return {
    [ENABLE_AI_FEATURES]: {
      name: i18n.translate('core.ui_settings.params.enableAIFeaturesTitle', {
        defaultMessage: 'Enable AI features',
      }),
      value: true,
      description: i18n.translate('core.ui_settings.params.enableAIFeaturesText', {
        defaultMessage: 'The setting to enable all AI-powered features in OpenSearch Dashboards.',
      }),
      requiresPageReload: true,
      // Wazuh: commented out by Wazuh. Scoped to dashboard admins, nobody could change it on a
      // default installation because opensearchDashboards.dashboardAdmin is empty.
      // scope: UiSettingScope.DASHBOARD_ADMIN,
      // Wazuh: hidden until the UI settings service finds the ML Commons plugin in the indexer.
      readonly: true,
      schema: schema.boolean(),
    },
  };
};
