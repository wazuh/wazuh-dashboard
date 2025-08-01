/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { BehaviorSubject } from 'rxjs';
import { UiSettingsServiceStart } from 'opensearch-dashboards/server';
import { HttpSetup } from '../http';
import { NotificationsStart } from '../notifications';
import { ChromeStart } from '../chrome';

export interface HealthCheckStatus {
  status: 'green' | 'yellow' | 'red' | 'gray' | null;
  checks: any[];
}

export interface HealthCheckServiceStartDeps {
  http: HttpSetup;
  notifications: NotificationsStart;
  chrome: ChromeStart;
  uiSettings: UiSettingsServiceStart;
}

export interface HealthCheckServiceSetup {
  status$: BehaviorSubject<{ ok: boolean | null; checks: any[] }>;
}

export interface HealthCheckServiceStart {
  status$: BehaviorSubject<{ ok: boolean | null; checks: any[] }>;
  client: {
    internal: {
      fetch: () => Promise<any>; // TODO: replace type by task
      run: () => Promise<any>; // TODO: replace type by task
    };
  };
}
