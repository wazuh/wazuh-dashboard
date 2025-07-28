/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */
import { Logger } from '@osd/logging';
import { TASK } from './constants';

type TaskRunStatusEnum = typeof TASK['RUN_STATUS'];

export type TaskRunStatus = TaskRunStatusEnum[keyof TaskRunStatusEnum];

type TaskRunResultEnum = typeof TASK['RUN_RESULT'];

export type TaskRunResult = TaskRunResultEnum[keyof TaskRunResultEnum];

export interface TaskDefinition {
  name: string;
  run: (ctx: any) => any;
  // Define the order to execute the task. Multiple task can take the same order and they will be executed in parallel
  order?: number;
  // Other metafields
  [key: string]: any;
}
export interface TaskInfo<M = null> {
  name: string;
  status: TaskRunStatus;
  result: TaskRunResult;
  createdAt: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  duration: number | null; // seconds
  data: any;
  error: string | null;
  _meta: M;
}

export interface ITask extends TaskInfo {
  run: <Context = any, Result = any>(ctx: Context) => Promise<Result>;
  getInfo: () => TaskInfo;
}

// Task manager
export interface TaskManager<S> {
  register: (task: TaskDefinition) => void;
  get: (name: string) => ITask;
  getAll: () => ITask[];
}

export interface TaskManagerRunTaskContext<S, C> {
  services: S;
  context: C;
  logger: Logger;
}
