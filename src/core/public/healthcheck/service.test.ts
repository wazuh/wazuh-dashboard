/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { first } from 'rxjs/operators';
import { HealthcheckService } from './service';
import { HealthCheckConfig, TaskInfo } from 'src/core/common/healthcheck';
import { httpServiceMock } from '../http/http_service.mock';
import { notificationServiceMock } from '../notifications/notifications_service.mock';
import { chromeServiceMock } from '../chrome/chrome_service.mock';
import { uiSettingsServiceMock } from '../ui_settings/ui_settings_service.mock';

const initialChecks = [
  { name: 'task:1', result: 'green', status: 'finished' },
  { name: 'task:2', result: 'green', status: 'finished' },
];
const runChecks = [{ name: 'task:2', result: 'red', status: 'finished' }];
const mergedChecks = [
  { name: 'task:1', result: 'green', status: 'finished' },
  { name: 'task:2', result: 'red', status: 'finished' },
];

const check = (name: string, overrides: Partial<TaskInfo>): TaskInfo =>
  ({ name, status: 'finished', critical: false, ...overrides } as TaskInfo);

describe('HealthcheckService', () => {
  it('ensure mount is called on start', async () => {
    const service = new HealthcheckService();

    const core = {
      http: httpServiceMock.createStartContract(),
      notifications: notificationServiceMock.createStartContract(),
      chrome: chromeServiceMock.createStartContract(),
      uiSettings: uiSettingsServiceMock.createStartContract(),
      healthCheckConfig: {} as HealthCheckConfig,
    };

    service.start(core);
  });

  // Disabled because the run checks is not allowed
  it.skip('fetch-run', async () => {
    const service = new HealthcheckService();

    const core = {
      http: httpServiceMock.createStartContract(),
      notifications: notificationServiceMock.createStartContract(),
      chrome: chromeServiceMock.createStartContract(),
      uiSettings: uiSettingsServiceMock.createStartContract(),
      healthCheckConfig: {} as HealthCheckConfig,
    };

    const start = service.start(core);

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
    scenario                                    | checks                                                                                           | status
    ${'there are no checks'}                    | ${[]}                                                                                            | ${'green'}
    ${'every check is green'}                   | ${[check('task:1', { result: 'green' }), check('task:2', { result: 'green' })]}                  | ${'green'}
    ${'a critical check is green'}              | ${[check('task:1', { result: 'green', critical: true })]}                                        | ${'green'}
    ${'a non critical check is red'}            | ${[check('task:1', { result: 'green' }), check('task:2', { result: 'red' })]}                    | ${'red'}
    ${'a critical check is red'}                | ${[check('task:1', { result: 'green' }), check('task:2', { result: 'red', critical: true })]}    | ${'red'}
    ${'a non critical check is yellow'}         | ${[check('task:1', { result: 'green' }), check('task:2', { result: 'yellow' })]}                 | ${'yellow'}
    ${'a critical check is yellow'}             | ${[check('task:1', { result: 'yellow', critical: true })]}                                       | ${'red'}
    ${'a red check and a yellow check coexist'} | ${[check('task:1', { result: 'yellow' }), check('task:2', { result: 'red' })]}                   | ${'red'}
    ${'a red check has not finished'}           | ${[check('task:1', { result: 'red', status: 'running' })]}                                       | ${'green'}
    ${'a critical check has not started'}       | ${[check('task:1', { result: 'gray', status: 'not_started', critical: true })]}                  | ${'green'}
    ${'an unfinished check hides a green one'}  | ${[check('task:1', { result: 'green' }), check('task:2', { result: 'red', status: 'running' })]} | ${'green'}
  `('computeOverallStatus returns $status when $scenario', async ({ checks, status }) => {
    const service = new HealthcheckService();

    expect(service.computeOverallStatus(checks)).toBe(status);
  });

  it('generateNextState computes the status and sorts the checks by name', async () => {
    const service = new HealthcheckService();
    const checks = [check('task:2', { result: 'red' }), check('task:1', { result: 'green' })];

    expect(service.generateNextState({ checks })).toEqual({
      status: 'red',
      checks: [check('task:1', { result: 'green' }), check('task:2', { result: 'red' })],
    });
  });

  it('generateNextState reports green when every check is green', async () => {
    const service = new HealthcheckService();
    const checks = [check('task:1', { result: 'green' }), check('task:2', { result: 'green' })];

    expect(service.generateNextState({ checks })).toEqual({ status: 'green', checks });
  });
});
