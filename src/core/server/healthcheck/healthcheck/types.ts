/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { LifecycleService, WazuhCoreServices } from '../types'; // TODO: fix
import { CoreStart, Logger } from '../../../../../core/server'; // TODO: fix

import { INITIALIZATION_TASK } from './constants';
import { ITask, TaskDefinition, TaskInfo } from '../task/types';

type RunStatusEnum = typeof INITIALIZATION_TASK['RUN_STATUS'];

export type InitializationTaskRunStatus = RunStatusEnum[keyof RunStatusEnum];

type RunResultEnum = typeof INITIALIZATION_TASK['RUN_RESULT'];

export type InitializationTaskRunResult = RunResultEnum[keyof RunResultEnum];

type ContextEnum = typeof INITIALIZATION_TASK['CONTEXT'];

export type InitializationTaskContext = ContextEnum[keyof ContextEnum];

export interface InitializationTaskDefinition {
  name: string;
  run: (ctx: any) => any;
  // Define the order to execute the task. Multiple task can take the same order and they will be executed in parallel
  order?: number;
}

export interface InitializationTaskRunData {
  name: InitializationTaskDefinition['name'];
  status: InitializationTaskRunStatus;
  result: InitializationTaskRunResult;
  createdAt: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  duration: number | null; // seconds
  data: any;
  error: string | null;
}

export interface IInitializationTask extends InitializationTaskRunData {
  run: <Context = any, Result = any>(ctx: Context) => Promise<Result>;
  getInfo: () => InitializationTaskRunData;
}

export interface IInitializationService extends LifecycleService<any, any, any, any, any, any> {
  register: (task: InitializationTaskDefinition) => void;
  get: (taskName: string) => InitializationTaskRunData;
  getAll: () => InitializationTaskRunData[];
  createRunContext: <ContextType = any>(
    scope: InitializationTaskContext,
    context: ContextType
  ) => {
    scope: InitializationTaskContext;
  };
  runAsInternal: <ReturnType = any>(tasks?: string[]) => Promise<ReturnType>;
}

export interface InitializationTaskRunContext extends WazuhCoreServices {
  core: CoreStart;
  logger: Logger;
  scope: InitializationTaskContext;
}

// Healcheck
export interface HealthCheckServiceSetup {
  register: (task: TaskDefinition) => void;
  get: (name: string) => ITask;
  getAll: () => ITask[];
  subscribe: (fn: () => void) => void;
}

export type HealthCheckServiceStart = HealthCheckServiceSetup;
