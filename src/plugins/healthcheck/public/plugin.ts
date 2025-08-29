import { i18n } from '@osd/i18n';
import {
  AppMountParameters,
  CoreSetup,
  CoreStart,
  DEFAULT_APP_CATEGORIES,
  Plugin,
} from '../../../core/public';
import { HealtcheckPluginSetup, HealtcheckPluginStart, AppPluginStartDependencies } from './types';
import { PLUGIN_ID, PLUGIN_NAME } from '../common';
import { setCore, setHealthCheck } from './dashboards_services';

export class HealtcheckPlugin implements Plugin<HealtcheckPluginSetup, HealtcheckPluginStart> {
  public setup(core: CoreSetup): HealtcheckPluginSetup {
    // Register an application into the side navigation menu
    core.application.register({
      id: PLUGIN_ID,
      title: PLUGIN_NAME,
      category: DEFAULT_APP_CATEGORIES.dashboardManagement,
      async mount(params: AppMountParameters) {
        // Load application bundle
        const { renderApp } = await import('./application');
        // Get start services as specified in opensearch_dashboards.json
        const [coreStart, depsStart] = await core.getStartServices();
        // Render the application
        return renderApp(coreStart, depsStart as AppPluginStartDependencies, params);
      },
    });

    return {};
  }

  public start(core: CoreStart): HealtcheckPluginStart {
    setHealthCheck(core.healthCheck);
    setCore(core);

    return {};
  }

  public stop() {}
}
