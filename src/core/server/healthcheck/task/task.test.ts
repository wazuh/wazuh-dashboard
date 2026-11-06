/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { Task } from './task';
import { taskResult } from '../../../common/healthcheck';
import { TaskDefinition } from './types';

const unbranded = (value: any): TaskDefinition['run'] => () => value;

describe('Task', () => {
  it('create task and ensure this has the expected fields in the info', async () => {
    const task = new Task({
      name: 'test',
      run: () => taskResult.ok(),
      critical: false,
    });

    const info = task.getInfo();

    expect(info.critical).toBe(false);
    expect(info.createdAt).toBeDefined();
    expect(info.data).toBe(null);
    expect(info.duration).toBe(null);
    expect(info.error).toBe(null);
    expect(info.finishedAt).toBe(null);
    expect(info.name).toBe('test');
    expect(info.status).toBe('not_started');
    expect(info.result).toBe('gray');
    expect(info.startedAt).toBe(null);
  });

  it('run task', async () => {
    const taskDefinition = {
      name: 'test',
      run: jest.fn(() => taskResult.ok('result:ok')),
      critical: false,
    };
    const task = new Task(taskDefinition);

    const infoRun = await task.run();

    expect(infoRun.critical).toBe(false);
    expect(infoRun.createdAt).toBeDefined();
    expect(infoRun.data).toBe('result:ok');
    expect(infoRun.duration).toBeDefined();
    expect(infoRun.error).toBe(null);
    expect(infoRun.finishedAt).toBeDefined();
    expect(infoRun.name).toBe('test');
    expect(infoRun.status).toBe('finished');
    expect(infoRun.result).toBe('green');
    expect(infoRun.startedAt).toBeDefined();

    expect(taskDefinition.run).toHaveBeenCalledTimes(1);

    const info = task.getInfo();

    expect(infoRun.critical).toBe(false);
    expect(info.createdAt).toBeDefined();
    expect(info.data).toBe('result:ok');
    expect(info.duration).toBeDefined();
    expect(info.error).toBe(null);
    expect(info.finishedAt).toBeDefined();
    expect(info.name).toBe('test');
    expect(info.status).toBe('finished');
    expect(info.result).toBe('green');
    expect(info.startedAt).toBeDefined();
  });

  it('run task with warning', async () => {
    const taskDefinition = {
      name: 'test',
      run: jest.fn(() => {
        throw new Error('test:warning');
      }),
      critical: false,
    };
    const task = new Task(taskDefinition);

    await expect(async () => await task.run()).rejects.toThrowError('test:warning');

    expect(taskDefinition.run).toHaveBeenCalledTimes(1);

    const info = task.getInfo();

    expect(info.critical).toBe(false);
    expect(info.createdAt).toBeDefined();
    expect(info.data).toBe(null);
    expect(info.duration).toBeDefined();
    expect(info.error).toBe('test:warning');
    expect(info.finishedAt).toBeDefined();
    expect(info.name).toBe('test');
    expect(info.status).toBe('finished');
    expect(info.result).toBe('yellow');
    expect(info.startedAt).toBeDefined();
  });

  it('run task with error', async () => {
    const taskDefinition = {
      name: 'test',
      run: jest.fn(() => {
        throw new Error('test:error');
      }),
      critical: true,
    };
    const task = new Task(taskDefinition);

    await expect(async () => await task.run()).rejects.toThrowError('test:error');

    expect(taskDefinition.run).toHaveBeenCalledTimes(1);

    const info = task.getInfo();

    expect(info.critical).toBe(true);
    expect(info.createdAt).toBeDefined();
    expect(info.data).toBe(null);
    expect(info.duration).toBeDefined();
    expect(info.error).toBe('test:error');
    expect(info.finishedAt).toBeDefined();
    expect(info.name).toBe('test');
    expect(info.status).toBe('finished');
    expect(info.result).toBe('red');
    expect(info.startedAt).toBeDefined();
  });

  it('run task returning an ok result', async () => {
    const task = new Task({
      name: 'test',
      run: jest.fn(() => taskResult.ok({ certificates: 3 })),
      critical: false,
    });

    const infoRun = await task.run();

    expect(infoRun.result).toBe('green');
    expect(infoRun.data).toEqual({ certificates: 3 });
    expect(infoRun.error).toBe(null);
  });

  it('run task returning a warning result', async () => {
    const task = new Task({
      name: 'test',
      run: jest.fn(() => taskResult.warning('expires in 20 days')),
      critical: false,
    });

    const infoRun = await task.run();

    expect(infoRun.result).toBe('yellow');
    expect(infoRun.error).toBe('expires in 20 days');
  });

  it('run task returning an error result does not throw', async () => {
    const task = new Task({
      name: 'test',
      run: jest.fn(() => taskResult.error('certificate expired')),
      critical: false,
    });

    const infoRun = await task.run();

    expect(infoRun.result).toBe('red');
    expect(infoRun.error).toBe('certificate expired');
  });

  // A non critical red is not selected by `failedCriticalChecks`, so the dashboard starts.
  it('run task returning an error result on a non critical task keeps it out of the failed critical checks', async () => {
    const task = new Task({
      name: 'test',
      run: jest.fn(() => taskResult.error('certificate expired')),
      critical: false,
    });

    const infoRun = await task.run();

    expect(infoRun.result).toBe('red');
    expect(infoRun.critical).toBe(false);
    expect(infoRun.status).toBe('finished');
  });

  it('run task returning an error result on a critical task keeps blocking', async () => {
    const task = new Task({
      name: 'test',
      run: jest.fn(() => taskResult.error('node unreachable')),
      critical: true,
    });

    const infoRun = await task.run();

    expect(infoRun.result).toBe('red');
    expect(infoRun.critical).toBe(true);
  });

  it.each([
    { status: 'ok' },
    { status: 'warning', message: 'm' },
    { status: 'error', message: 'm' },
  ])(
    'run task resolving %p unbranded rejects instead of reading it as a status',
    async (resolved) => {
      const task = new Task({
        name: 'test',
        run: unbranded(resolved),
        critical: false,
      });

      await expect(task.run()).rejects.toThrowError(/must return a TaskResult/);
    }
  );

  it.each([undefined, null, 'result:ok', 42, { certificates: 3 }])(
    'run task resolving %p unbranded rejects',
    async (resolved) => {
      const task = new Task({ name: 'test', run: unbranded(resolved), critical: false });

      await expect(task.run()).rejects.toThrowError(/must return a TaskResult/);
    }
  );

  it('run task resolving an unbranded value reports the failure in the info', async () => {
    const task = new Task({ name: 'test', run: unbranded('plain'), critical: false });

    await expect(task.run()).rejects.toThrowError();

    const info = task.getInfo();

    expect(info.status).toBe('finished');
    expect(info.result).toBe('yellow');
    expect(info.error).toMatch(/must return a TaskResult/);
    expect(info.data).toBe(null);
  });

  it('run task clears the error of a previous failed run', async () => {
    const run = jest
      .fn()
      .mockReturnValueOnce(taskResult.error('certificate expired'))
      .mockReturnValueOnce(taskResult.ok());
    const task = new Task({ name: 'test', run, critical: false });

    const firstRun = await task.run();
    expect(firstRun.result).toBe('red');

    const secondRun = await task.run();

    expect(secondRun.result).toBe('green');
    expect(secondRun.error).toBe(null);
  });
});
