/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { BehaviorSubject } from 'rxjs';

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
