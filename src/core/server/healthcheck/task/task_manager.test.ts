/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { TaskManager } from './task_manager';
import { TASK_RESULT } from '../../../common/healthcheck';

const mockLogger = (): any => {
  const logger: any = {
    debug: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    get: jest.fn(() => logger),
  };

  return logger;
};

describe('TaskManager run context', () => {
  it('provides the result constructors to the task', async () => {
    const manager = new TaskManager(mockLogger(), { some: 'service' });
    const run = jest.fn((ctx) => ctx.taskResult.ok({ certificates: 3 }));

    manager.register({ name: 'test', run });

    await manager.run({ scope: 'internal' });

    const ctx = run.mock.calls[0][0];

    expect(ctx.taskResult.ok).toEqual(expect.any(Function));
    expect(ctx.taskResult.warning).toEqual(expect.any(Function));
    expect(ctx.taskResult.error).toEqual(expect.any(Function));
  });

  it('keeps the services, context and logger it already provided', async () => {
    const services = { some: 'service' };
    const manager = new TaskManager(mockLogger(), services);
    const run = jest.fn((ctx) => ctx.taskResult.ok());

    manager.register({ name: 'test', run });

    await manager.run({ scope: 'internal' });

    const ctx = run.mock.calls[0][0];

    expect(ctx.services).toBe(services);
    expect(ctx.context).toEqual({ scope: 'internal' });
    expect(ctx.logger).toBeDefined();
  });

  it('brands a result built from the injected constructors', async () => {
    const manager = new TaskManager(mockLogger(), {});

    manager.register({
      name: 'test',
      run: (ctx) => ctx.taskResult.warning('expires in 20 days'),
    });

    const [info] = (await manager.run({ scope: 'internal' })) as any[];

    expect(info.result).toBe('yellow');
    expect(info.error).toBe('expires in 20 days');
  });

  it('accepts a result the task built without the injected constructors', async () => {
    const manager = new TaskManager(mockLogger(), {});

    manager.register({
      name: 'test',
      run: () => ({ [TASK_RESULT]: true, status: 'ok' as const }),
    });

    const [info] = (await manager.run({ scope: 'internal' })) as any[];

    expect(info.result).toBe('green');
  });
});
