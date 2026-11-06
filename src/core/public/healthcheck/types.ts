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
import { HealthCheckStatus } from './service';

export interface HealthCheckServiceStartDeps {
  http: HttpSetup;
  notifications: NotificationsStart;
  chrome: ChromeStart;
  uiSettings: IUiSettingsClient;
  healthCheckConfig: HealthCheckConfig;
}

/** Plain-language text for a check, shown instead of its technical name. */
export interface HealthCheckDescription {
  title: string;
  description: string;
  // What to do when the check fails.
  remediation: string;
}

export interface HealthCheckServiceSetup {
  status$: BehaviorSubject<{ status: TaskInfo['result']; checks: TaskInfo[] }>;
  describe: (name: string, description: HealthCheckDescription) => void;
}

export interface HealthCheckServiceStart {
  status$: BehaviorSubject<{ status: TaskInfo['result']; checks: TaskInfo[] }>;
  client: {
    internal: {
      fetch: (tasknames?: string[]) => Promise<HealthCheckStatus>;
      run: (tasknames?: string[]) => Promise<HealthCheckStatus>;
    };
  };
  getConfig: () => Promise<HealthCheckConfig>;
  getDescription: (name: string) => HealthCheckDescription | undefined;
}
