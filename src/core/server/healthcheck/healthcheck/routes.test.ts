/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { Server } from '@hapi/hapi';
import { taskResult } from '../../../common/healthcheck';
import { HealthCheck } from './health_check';
import { addRoutesNotReadyServer } from './routes';

function mockLogger(): any {
  return {
    trace: jest.fn(),
    debug: jest.fn(),
    log: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    fatal: jest.fn(),
    get: () => mockLogger(),
  };
}

const delayPromise = (time: number) => new Promise((res) => setTimeout(res, time));

describe('Not-ready server healthcheck routes', () => {
  let server: Server;
  let healthcheck: HealthCheck;
  const tasks = {
    critical: {
      name: 'critical',
      critical: true,
      run: jest.fn(async () => {
        await delayPromise(10);
        return taskResult.ok({ secret: 'critical-secret' });
      }),
    },
    critical2: {
      name: 'critical2',
      critical: true,
      run: jest.fn(async () => {
        await delayPromise(10);
        return taskResult.ok({ secret: 'critical2-secret' });
      }),
    },
    failingCritical: {
      name: 'failing-critical',
      critical: true,
      run: jest.fn(() => taskResult.error('critical failure')),
    },
    notCritical: {
      name: 'not-critical',
      run: jest.fn(() =>
        taskResult.warning('certificate on node secret-node expired', { secret: 'warning-secret' })
      ),
    },
    disabled: {
      name: 'disabled',
      critical: true,
      run: jest.fn(() => taskResult.ok({ secret: 'disabled-secret' })),
    },
  };

  beforeEach(async () => {
    Object.values(tasks).forEach(({ run }) => run.mockClear());
    healthcheck = new HealthCheck(mockLogger());
    Object.values(tasks).forEach((task) => healthcheck.register(task));
    // HealthCheck.start sets this from checks_enabled
    healthcheck.getAll().forEach((item) => {
      item.enabled = item.name !== 'disabled';
    });
    server = new Server();
    addRoutesNotReadyServer(server, { healthcheck, logger: mockLogger() });
  });

  it('runs an enabled critical task without returning its data', async () => {
    const response = await server.inject({
      method: 'POST',
      url: '/api/healthcheck/internal?name=critical',
    });

    expect(response.statusCode).toBe(200);
    expect(tasks.critical.run).toHaveBeenCalledTimes(1);
    const body = JSON.parse(response.payload);
    expect(body.tasks).toHaveLength(1);
    expect(body.tasks[0]).toMatchObject({ name: 'critical', result: 'green' });
    expect(body.tasks[0]).not.toHaveProperty('data');
    expect(response.payload).not.toContain('secret');
  });

  it.each([
    ['a disabled task', '?name=disabled'],
    ['a non-critical task', '?name=not-critical'],
    ['an unknown task', '?name=unknown'],
    ['an empty task name', '?name='],
    ['no task name', ''],
    ['a mix of allowed and not allowed tasks', '?name=critical,not-critical'],
  ])('rejects running %s', async (_, query) => {
    const response = await server.inject({
      method: 'POST',
      url: `/api/healthcheck/internal${query}`,
    });

    expect(response.statusCode).toBe(400);
    Object.values(tasks).forEach(({ run }) => expect(run).not.toHaveBeenCalled());
  });

  it('shares one run between reordered or repeated task names', async () => {
    const runWithDecorators = jest.spyOn(healthcheck, 'runWithDecorators');

    const responses = await Promise.all(
      ['critical,critical2', 'critical2,critical', 'critical,critical2,critical'].map((names) =>
        server.inject({ method: 'POST', url: `/api/healthcheck/internal?name=${names}` })
      )
    );

    responses.forEach(({ statusCode }) => expect(statusCode).toBe(200));
    expect(runWithDecorators).toHaveBeenCalledTimes(1);
    expect(runWithDecorators).toHaveBeenCalledWith(expect.anything(), ['critical', 'critical2']);
  });

  it('returns the tasks status without their data or non-critical errors', async () => {
    await healthcheck.run({}, ['critical', 'failing-critical', 'not-critical']);

    const response = await server.inject({ method: 'GET', url: '/api/healthcheck/internal' });

    expect(response.statusCode).toBe(200);
    const body = JSON.parse(response.payload);
    expect(body.tasks).toHaveLength(Object.keys(tasks).length);
    body.tasks.forEach((task: object) => expect(task).not.toHaveProperty('data'));
    expect(response.payload).not.toContain('secret');

    const byName = (name: string) =>
      body.tasks.find((task: { name: string }) => task.name === name);
    expect(byName('failing-critical').error).toBe('critical failure');
    expect(byName('not-critical').error).toBe(
      'Check reported a problem. Log in, or check the server logs, for details.'
    );
    expect(byName('critical').error).toBeNull();
  });
});
