import './index.scss';

import { HealtcheckPlugin } from './plugin';

// This exports static code and TypeScript types,
// as well as, OpenSearch Dashboards Platform `plugin()` initializer.
export function plugin() {
  return new HealtcheckPlugin();
}
export { HealtcheckPluginSetup, HealtcheckPluginStart } from './types';
