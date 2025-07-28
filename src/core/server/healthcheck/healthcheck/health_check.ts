/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { Logger } from 'opensearch-dashboards/server';
import { BehaviorSubject, Subscription } from 'rxjs';
import { retry, TASK, TaskManager } from '../task';
import type { TaskRunResult } from '../task';
import { addRoutes } from './routes';
import { ScheduledIntervalTask } from './scheduled_task';

export interface HealthCheckStatus {
  ok: boolean | null;
  checks: any[] | null;
  error?: string | null;
}

export class HealthCheck extends TaskManager implements TaskManager {
  private items = new Map();
  status$: BehaviorSubject<HealthCheckStatus> = new BehaviorSubject({
    ok: null,
    checks: [],
    error: null,
  });
  private statusSubscriptions: Subscription = new Subscription();
  private _retryDelay: number = 0;
  private _maxRetryAttempts: number = 0;
  private _internalScheduledCheckTime: number = 0;
  private scheduled?: ScheduledIntervalTask;
  private _coreStartServices: any;
  constructor(private readonly logger: Logger, services: any) {
    super(logger, services);
  }

  getCheckInfo(taskName: string) {
    const task = this.get(taskName);
    return task.getInfo();
  }

  getChecksInfo(taskNames?: string[]) {
    const tasks: string[] = taskNames || [...this.items.keys()];

    return tasks.map((taskName) => this.getCheckInfo(taskName));
  }

  setCheckResult(name: string, result: TaskRunResult) {
    const task = this.get(name);

    if (task) {
      task.result = result;
    }
  }

  async setup(
    core: any,
    config: { retries_delay: number; max_retries: number; schedule_interval: number }
  ) {
    this._retryDelay = config.retries_delay.asMilliseconds();
    this._maxRetryAttempts = config.max_retries;
    this._internalScheduledCheckTime = config.schedule_interval.asMilliseconds();

    const router = core.http.createRouter('/api/healthcheck');
    addRoutes(router, { healthcheck: this, logger: this.logger });
  }

  async runInternal() {
    return this.run({ services: { core: this._coreStartServices }, scope: 'internal' });
  }

  async runInitialCheck() {
    return new Promise<void>((res) => {
      this.runInternal().catch(() => {});

      this.status$.subscribe(({ ok }) => {
        if (ok) {
          res();
        }
      });
    });
  }

  async start(core: any) {
    this._coreStartServices = core;
    this.logger.debug(`Waiting until all checks are ok...`);

    await this.runInitialCheck();
    this.logger.info(`Checks are ok`);

    this.logger.debug(`Setting scheduled checks`);
    this.scheduled = new ScheduledIntervalTask(async () => {
      try {
        this.logger.debug(`Running scheduled check`);
        await this.runInternal();
      } catch (error) {
        this.logger.error(`Error in scheduled check: ${error.message}`);
      } finally {
        this.logger.debug('Scheduled check finished');
      }
    }, this._internalScheduledCheckTime);
    this.scheduled.start();
    this.logger.info(`Set scheduled checks each ${this._internalScheduledCheckTime}ms`);
  }

  async stop() {
    this.logger.debug('Stop starts');
    this.scheduled?.stop();
    this.statusSubscriptions.unsubscribe();
    this.logger.debug('Stop finished');
  }

  async _run(ctx, taskNames) {
    let ok: null | boolean = null;
    let checks: any[] = [];
    let error = null;
    try {
      this.logger.debug('Starting');
      if (this.items.size === 0) {
        this.logger.debug('No checks. Skipping');
        ok = true;
      } else {
        this.logger.debug('Running checks');

        checks = await super.run(ctx, taskNames);
        ok =
          Array.isArray(checks) &&
          checks.every(
            ({ status, result, ..._meta }) =>
              status === TASK.RUN_STATUS.FINISHED &&
              (_meta?.isCritical ? result === TASK.RUN_RESULT.SUCCESS : true)
          );
      }

      this.logger.debug(`ok: [${ok}]. checks [${checks?.length}]`);
    } catch (err) {
      this.logger.error(`There an error: ${err.message}`);
      ok = false;
      error = err.message;
    }

    const data = {
      ok,
      checks,
      error,
    };

    if (error) {
      throw error;
    }

    return data;
  }

  async run(...args) {
    return retry(
      async (...params) => {
        const data = await this._run(...params);
        if (data.error) {
          throw new Error(data.error);
        }
        const failedCriticalChecks = data.checks?.filter(
          ({ status, result, _meta = {} }) =>
            status === TASK.RUN_STATUS.FINISHED &&
            result === TASK.RUN_RESULT.FAIL &&
            _meta?.isCritical
        );
        if (failedCriticalChecks?.length) {
          throw new Error(
            `Some checks failed: [${failedCriticalChecks.length}/${data.checks.length}]`
          );
        }
        // Emit message through observer
        this.status$.next(data);
      },
      {
        maxAttempts: this._maxRetryAttempts,
        delay: this._retryDelay,
      }
    )(...args);
  }

  /**
   * Subscribe to changes in the health check
   * @param fn
   * @returns
   */
  subscribe(fn: (params: HealthCheckStatus) => void) {
    const subscription = this.status$.subscribe(fn);
    this.statusSubscriptions.add(subscription);
    return subscription;
  }
}
