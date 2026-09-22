/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { i18n } from '@osd/i18n';
import {
  AppMountParameters,
  CoreSetup,
  CoreStart,
  DEFAULT_APP_CATEGORIES,
  Plugin,
  PluginInitializerContext,
} from 'opensearch-dashboards/public';
import { ABOUT_PLUGIN_ID } from '../common/constants';
import type { AboutConfigType } from '../common/config';

// eslint-disable-next-line @typescript-eslint/no-empty-interface
export interface AboutPluginSetup {}
// eslint-disable-next-line @typescript-eslint/no-empty-interface
export interface AboutPluginStart {}

export class AboutPlugin implements Plugin<AboutPluginSetup, AboutPluginStart> {
  constructor(private readonly initializerContext: PluginInitializerContext) {}

  public setup(core: CoreSetup): AboutPluginSetup {
    const config = this.initializerContext.config.get<AboutConfigType>();

    core.application.register({
      id: ABOUT_PLUGIN_ID,
      title: i18n.translate('about.appTitle', { defaultMessage: 'About' }),
      // Wazuh: same "Dashboard management" category and position the About
      // app was in before it moved out of wazuh-dashboard-plugins.
      category: DEFAULT_APP_CATEGORIES.dashboardManagement,
      order: 10006,
      mount: async (params: AppMountParameters) => {
        const { element } = params;
        const [coreStart] = await core.getStartServices();
        const { renderApp } = await import('./application');
        return renderApp(coreStart, config, element);
      },
    });

    return {};
  }

  public start(_core: CoreStart): AboutPluginStart {
    return {};
  }
}
