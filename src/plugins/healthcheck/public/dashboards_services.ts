import { CoreStart } from '../../../core/public';
import { HealthCheckServiceStart } from '../../../core/public/healthcheck';
import { createGetterSetter } from '../../opensearch_dashboards_utils/common';

export const [getHealthCheck, setHealthCheck] = createGetterSetter<HealthCheckServiceStart>(
  'HealthCheck'
);
export const [getCore, setCore] = createGetterSetter<CoreStart>('CoreStart');
