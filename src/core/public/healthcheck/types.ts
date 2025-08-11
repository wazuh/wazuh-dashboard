/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { BehaviorSubject } from 'rxjs';
import { UiSettingsServiceStart } from 'opensearch-dashboards/server';
import { HttpSetup } from '../http';
import { NotificationsStart } from '../notifications';
import { ChromeStart } from '../chrome';
import { HealthCheckConfig, HealthCheckStatus } from '../../common/healthcheck';

export interface HealthCheckServiceStartDeps {
  http: HttpSetup;
  notifications: NotificationsStart;
  chrome: ChromeStart;
  uiSettings: UiSettingsServiceStart;
  healthCheckConfig: HealthCheckConfig;
}

export interface HealthCheckServiceSetup {
  status$: BehaviorSubject<{ ok: boolean | null; checks: any[] }>;
}

export interface HealthCheckServiceStart {
  status$: BehaviorSubject<{ ok: boolean | null; checks: any[] }>;
  client: {
    internal: {
      fetch: (tasknames?: string[]) => Promise<HealthCheckStatus>;
      run: (tasknames?: string[]) => Promise<HealthCheckStatus>;
    };
  };
}
