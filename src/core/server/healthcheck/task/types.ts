/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */
import { Logger } from '@osd/logging';
import { TaskInfo, TaskResult, TaskResultFactory } from '../../../common/healthcheck';

export interface TaskRunContext<S = any, C = any> {
  services: S;
  context: C;
  logger: Logger;
  // Builds the result the task returns, so a task needs no import to report one.
  taskResult: TaskResultFactory;
}

export interface TaskDefinition<S = any, C = any> {
  name: string;
  run: (ctx: TaskRunContext<S, C>) => TaskResult | Promise<TaskResult>;
  // Define the order to execute the task. Multiple tasks can take the same order and they will be executed in parallel
  order?: number;
  critical?: boolean;
}

export interface ITask extends TaskInfo {
  runInternal: TaskDefinition['run'];
  order?: number;
  run: (...params: any[]) => Promise<TaskInfo>;
  getInfo: () => TaskInfo;
}

// Task manager
export interface TaskManager {
  register: (task: TaskDefinition) => void;
  get: (name: string) => ITask;
  getAll: () => ITask[];
}

export type TaskManagerRunTaskContext<S, C> = TaskRunContext<S, C>;
