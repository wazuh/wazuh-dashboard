/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { BehaviorSubject } from 'rxjs';
import { HttpSetup } from '../http';
import { NotificationsStart } from '../notifications';
import { ChromeStart } from '../chrome';
import { HealthCheckConfig, TaskInfo } from '../../common/healthcheck';
import { IUiSettingsClient } from '../ui_settings';

export interface HealthCheckServiceStartDeps {
  http: HttpSetup;
  notifications: NotificationsStart;
  chrome: ChromeStart;
  uiSettings: IUiSettingsClient;
  healthCheckConfig: HealthCheckConfig;
}

export interface HealthCheckServiceSetup {
  status$: BehaviorSubject<{ ok: boolean | null; checks: any[] }>;
}

export interface HealthCheckServiceStart {
  status$: BehaviorSubject<{ ok: boolean | null; checks: any[] }>;
  client: {
    internal: {
      fetch: (tasknames?: string[]) => Promise<TaskInfo[]>;
      run: (tasknames?: string[]) => Promise<TaskInfo[]>;
    };
  };
}
