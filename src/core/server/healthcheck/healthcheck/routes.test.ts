/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { Server } from '@hapi/hapi';
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

describe('Not-ready server healthcheck routes', () => {
  let server: Server;
  let healthcheck: HealthCheck;
  const tasks = {
    critical: { name: 'critical', critical: true, run: jest.fn(() => ({ secret: 'critical' })) },
    notCritical: { name: 'not-critical', run: jest.fn(() => ({ secret: 'not-critical' })) },
    disabled: { name: 'disabled', critical: true, run: jest.fn(() => ({ secret: 'disabled' })) },
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
    expect(body.tasks.map(({ name }: { name: string }) => name)).toEqual(['critical']);
    expect(body.tasks[0]).not.toHaveProperty('data');
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

  it('returns the tasks status without their data', async () => {
    await healthcheck.run({}, ['critical', 'not-critical']);

    const response = await server.inject({ method: 'GET', url: '/api/healthcheck/internal' });

    expect(response.statusCode).toBe(200);
    const body = JSON.parse(response.payload);
    expect(body.tasks).toHaveLength(3);
    body.tasks.forEach((task: object) => expect(task).not.toHaveProperty('data'));
    expect(response.payload).not.toContain('secret');
  });
});
