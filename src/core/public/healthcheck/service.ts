/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { BehaviorSubject } from 'rxjs';
import { mount } from './ui/mount';

export class HealthcheckService {
  status$: BehaviorSubject<{ ok: boolean | null; checks: any[] }> = new BehaviorSubject({
    ok: null,
    checks: [],
  });
  constructor() {}
  setup() {
    const deps = {
      status$: this.status$,
    };
    return deps;
  }
  start(core: any) {
    const status$ = this.status$;
    const deps = {
      status$: this.status$,
      client: {
        internal: {
          async fetch() {
            const response = await core.http.get('/api/healthcheck/internal');
            status$.next({ ok: true, checks: response.tasks });
            return response;
          },
          async run() {
            const response = await core.http.post('/api/healthcheck/internal');
            status$.next({ ok: true, checks: response.tasks });
            return response;
          },
        },
      },
    };

    // Mount UI button
    mount({
      coreStart: core,
      status$: this.status$,
      fetch: deps.client.internal.fetch,
      run: deps.client.internal.run,
    });

    return deps;
  }
  stop() {}
}
