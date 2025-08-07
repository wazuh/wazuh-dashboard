/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { first } from 'rxjs/operators';
import { HealthcheckService } from './service';
import { mount as mountUI } from './ui/mount';

jest.mock('./ui/mount', () => ({ mount: jest.fn() }));

const initialChecks = [
  { name: 'task:1', result: 'green', status: 'finished', _meta: {} },
  { name: 'task:2', result: 'green', status: 'finished', _meta: {} },
];
const runChecks = [{ name: 'task:2', result: 'red', status: 'finished', _meta: {} }];
const mergedChecks = [
  { name: 'task:1', result: 'green', status: 'finished', _meta: {} },
  { name: 'task:2', result: 'red', status: 'finished', _meta: {} },
];

describe('HealthcheckService', () => {
  it('ensure mount is called on start', async () => {
    const service = new HealthcheckService();

    const core = {
      http: {
        get: jest.fn(() => ({
          tasks: initialChecks,
        })),
        post: jest.fn(() => ({
          tasks: runChecks,
        })),
      },
    };

    await service.start(core);

    expect(mountUI).toBeCalledTimes(1);
  });

  it('fetch-run', async () => {
    const service = new HealthcheckService();

    const core = {
      http: {
        get: jest.fn(() => ({
          tasks: initialChecks,
        })),
        post: jest.fn(() => ({
          tasks: runChecks,
        })),
      },
    };

    const start = await service.start(core);

    const responseFetch = await start.client.internal.fetch();
    expect(responseFetch.checks).toEqual(initialChecks);

    expect((await start.status$.pipe(first()).toPromise()).checks).toEqual(initialChecks);

    const responseRun = await start.client.internal.run();
    expect(responseRun.checks).toEqual(runChecks);

    expect((await start.status$.pipe(first()).toPromise()).checks).toEqual(mergedChecks);

    const responseFetch2 = await start.client.internal.fetch();
    expect(responseFetch2.checks).toEqual(initialChecks);
  });

  it.each`
    checks                                                                                                                                                        | status
    ${[{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'green', status: 'finished', _meta: {} }]}                   | ${'green'}
    ${[{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'red', status: 'finished', _meta: {} }]}                     | ${'yellow'}
    ${[{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'green', status: 'finished', _meta: { isCritical: true } }]} | ${'green'}
    ${[{ name: 'task:1', result: 'red', status: 'finished', _meta: {} }, { name: 'task:2', result: 'green', status: 'finished', _meta: { isCritical: true } }]}   | ${'yellow'}
    ${[{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'red', status: 'finished', _meta: { isCritical: true } }]}   | ${'red'}
    ${[{ name: 'task:1', result: 'red', status: 'finished', _meta: {} }, { name: 'task:2', result: 'red', status: 'finished', _meta: { isCritical: true } }]}     | ${'red'}
  `('compute status overall', async ({ checks, status }) => {
    const service = new HealthcheckService();

    expect(service.computeOverallStatus(checks)).toBe(status);
  });

  it.each`
    checks                                                                | status
    ${{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }} | ${'green'}
    ${{ name: 'task:1', result: 'red', status: 'finished', _meta: {} }}   | ${'red'}
  `('compute check status', async ({ checks, status }) => {
    const service = new HealthcheckService();

    expect(service.computeStatus(checks)).toBe(status);
  });

  it.each`
    checks                                                                                                                                                        | result
    ${[{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'green', status: 'finished', _meta: {} }]}                   | ${{ status: 'green', checks: [{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'green', status: 'finished', _meta: {} }] }}
    ${[{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'red', status: 'finished', _meta: {} }]}                     | ${{ status: 'yellow', checks: [{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'red', status: 'finished', _meta: {} }] }}
    ${[{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'green', status: 'finished', _meta: { isCritical: true } }]} | ${{ status: 'green', checks: [{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'green', status: 'finished', _meta: { isCritical: true } }] }}
    ${[{ name: 'task:1', result: 'red', status: 'finished', _meta: {} }, { name: 'task:2', result: 'green', status: 'finished', _meta: { isCritical: true } }]}   | ${{ status: 'yellow', checks: [{ name: 'task:1', result: 'red', status: 'finished', _meta: {} }, { name: 'task:2', result: 'green', status: 'finished', _meta: { isCritical: true } }] }}
    ${[{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'red', status: 'finished', _meta: { isCritical: true } }]}   | ${{ status: 'red', checks: [{ name: 'task:1', result: 'green', status: 'finished', _meta: {} }, { name: 'task:2', result: 'red', status: 'finished', _meta: { isCritical: true } }] }}
    ${[{ name: 'task:1', result: 'red', status: 'finished', _meta: {} }, { name: 'task:2', result: 'red', status: 'finished', _meta: { isCritical: true } }]}     | ${{ status: 'red', checks: [{ name: 'task:1', result: 'red', status: 'finished', _meta: {} }, { name: 'task:2', result: 'red', status: 'finished', _meta: { isCritical: true } }] }}
  `('generateNextState', async ({ checks, result }) => {
    const service = new HealthcheckService();

    expect(service.generateNextState({ checks })).toEqual(result);
  });
});
