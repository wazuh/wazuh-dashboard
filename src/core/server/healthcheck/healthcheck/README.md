# HealthCheck

The `HealthCheck` provides a mechanism to see and manage the health of checks.

> :warning: In this stage, this only runs in the internal context that only can apply to the `Global` tenant if multitenancy is enabled.

This allows to register the check tasks that can be used by the plugin in the `setup` lifecycle.

# Configuration

| setting                                             | description                                                                                                            | default value     | allowed values            |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------- | ------------------------- |
| `healthcheck.enabled`                               | define if the health check is enabled or not                                                                           | true              | true, false               |
| `healthcheck.checks_enabled`                        | define the checks that are enabled. This is a regular expression or a list of regular expressions (NodeJS compatibles) | `.*`              | string or list of strings |
| `healthcheck.interval`                              | define the interval to run the health check after the initial check                                                    | 15m               | 5m to 24h                 |
| `healthcheck.retries_delay`                         | define the wait time after a failed overall health check                                                               | 2.5s              | 0 to 1m                   |
| `healthcheck.max_retries`                           | define the maximum count of retries of the overall health check that can be executed                                   | 5                 | integer, minimum 1        |
| `healthcheck.server_not_ready_troubleshooting_link` | define the troubleshooting link in the not-ready server                                                                | URL to Wazuh docs | a valid URL               |

## Enabling checks

By default all the checks are enabled.

The user can configure the enabled checks using the `healthcheck.checks_enabled` setting.

For example, assumming the following checks are registered:

- task1
- task2
- another-task
- another-check

Examples To only enable the `task1` and `task2` checks, you can provide the following configuration:

```xml
healthcheck.checks_enabled: '^test.*' # Enable the task1 and task2. Start with "test" and then any character
healthcheck.checks_enabled: ['^test1$', '^another-task$'] # Enable the task1 and another-task.
healthcheck.checks_enabled: '^another.*' # Enable the another-task and another-check.
healthcheck.checks_enabled: 'task.*' # Enable the task1, task2, another-task.
```

# Lyfecycle

## Server

1. Setup the health check

1.1. Setup the configuration

1.2. Register API endpoints routes

2. Register check task in the plugin `setup` lifecycle

3. Start the health check

If this is enabled:

3.1. Mark the enabled task according to the `checks_enabled` filter

3.2. Run the initial check. If some critical task fails, then the dashboard server will be blocked in the `server is not ready yet` view

3.3. Once passed the initial check, this sets a scheduled check, to update the check status

```
  server    log   [10:04:59.857] [info][healthcheck] Checks are ok
  server    log   [10:04:59.857] [info][healthcheck] Set scheduled checks each 300000ms
```

3.4. Continue the server startup

## Frontend

1. Setup the health check
2. Start the health check
   If this is enabled, then this register a button to be mounted in the menu

Other plugins can register tasks in the plugin `setup` lifecycle that will be run on the server starts lifecycle.

Optionally the registered tasks could be retrieved to run in API endpoints or getting information about its status.

# Scopes

The scopes can be used to get a specific context (clients, parameters) that is set in the `scope` property of the task context.

> :warning: In this stage, this only runs in the internal context that only can apply to the `Global` tenant if multitenancy is enabled.

The `internal` scoped tasks keep the same execution data (see [Task execution data](#task-execution-data)).

When the app starts, all the registered tasks run for the `internal` scope.

# Tasks

## Task definition interface

A task can be defined with:

```ts
export interface TaskDefinition {
  // Task identifier. This should be unique. See the name convention.
  name: string;
  // Returns the result of the check. See "Reporting a result".
  run: (ctx: TaskRunContext) => TaskResult | Promise<TaskResult>;
  /* Define the order to execute the task. Multiple task can take the same order and they will be executed in parallel.
  If it is not defined, the task will be executed as last order group. */
  order?: number;
  /* Define if the task is critical. A critical task reporting `red` blocks the
  initialization. It does not decide the result color, the task does. */
  critical?: boolean;
}
```

## Register a task

```ts
// plugin setup
setup(core){

  // Register a task
  core.healthCheck.register({
    name: 'custom-task',
    run: async (ctx) => {
      const certificates = await readCertificates(ctx.context.services.core);

      if (certificates.expired.length > 0) {
        return ctx.taskResult.error('Some certificates expired', certificates);
      }

      return ctx.taskResult.ok(certificates);
    },
    order: 1,
    critical: false
  });
}
```

## Reporting a result

The `ctx` a task receives carries the result constructors, so a task reports its
own result without importing anything:

```ts
ctx.taskResult.ok(data?)               // green
ctx.taskResult.warning(message, data?) // yellow
ctx.taskResult.error(message, data?)   // red
```

`message` becomes the task `error` field and is what the UI shows. `data` is
stored as the task `data` field for diagnostics.

A task that throws is still handled: the thrown message becomes `error`, and the
result is `red` when the task is `critical` and `yellow` when it is not. Throwing
is the path for the unexpected; returning a result is the path for what the check
set out to measure.

Returning anything else is rejected, with the task name in the message:

```
Task custom-task must return a TaskResult.
Use taskResult.ok, taskResult.warning or taskResult.error.
```

The result is branded with `Symbol.for('healthcheck.taskResult')`, so a result
built elsewhere is still recognised as long as it carries that brand.

## Task context

A task receives a `TaskRunContext`:

```ts
{
  services: {},                       // empty for health check tasks
  context: {
    services: { core },               // HealthCheckServiceStartDeps
    scope,                            // 'internal' | 'internal-initial' | 'internal-scheduled' | 'user'
  },
  logger,                             // scoped to the task name
  taskResult,                         // ok, warning and error constructors
}
```

`core` lives in `ctx.context.services.core`. The top level `ctx.services` is
empty.

Type a task against the contract instead of redeclaring it:

```ts
import type { TaskDefinition } from 'opensearch-dashboards/server';

export const initializationTaskCreatorCustom = (): TaskDefinition => ({
  name: 'custom-task',
  run: async (ctx) => ctx.taskResult.ok(),
});
```

## Task name convention

- lowercase
- kebab case (`word1-word2`)
- use colon ( `:` ) for tasks related to some entity that have different sub entities.

```
entity_identifier:entity_specific
```

For example:

```
index-pattern:alerts
index-pattern:statistics
index-pattern:vulnerabilities-states
```

## Task execution data

The task has the following data related to the execution:

```ts
interface InitializationTaskRunData {
  name: string;
  status: 'not_started' | 'running' | 'finished';
  result: 'green' | 'yellow' | 'red' | 'gray' | null;
  createdAt: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  duration: number | null; // milliseconds
  data: any;
  error: string | null;
  enabled: boolean;
  critical: boolean;
}
```

## API

The backend service registers routes to manage the related data:

- `GET /api/healthcheck/config`: allow to retrieve the health check configuration.

- `GET /api/healthcheck/internal`: allow to retrieve the run info of the checks. This allows to use the `name` query parameter to get specific checks.

- `POST /api/healthcheck/internal`: allow to run info of the checks. This allows to use the `name` query parameter to get specific checks.

## Definitions and rules

- **Task / individual check**

  - status (only `not_started`, `in_progress`, or `finished`)
  - result (one of `green`, `yellow`, `red`, or `gray`)

    - `green`: OK
    - `yellow`: needs attention
    - `red`: failed
    - `gray`: unknown / not executed (typically because `status != "finished"`)

  - The task chooses its own result by returning `taskResult.ok`, `taskResult.warning` or `taskResult.error`.
  - A task that throws gets `red` when it is `critical`, and `yellow` when it is not.
  - **Failed** ⟶ when `status == "finished"` and `result` is `red` or `yellow`.
  - `critical` is task metadata set at registration. It decides whether a `red` result blocks the server from starting. It does not decide the result color.
    - `true` = **critical**; `false` or absent = **non-critical**.
  - A non-critical task can report `red`: the failure is visible everywhere the status is shown, and the server still starts.

Two separate aggregations read these results. They answer different questions and do not use the same rule.

- **Startup blocking** (the "server is not ready yet" screen)

  - A check blocks the server from starting when `critical == true` and `result == "red"`.
  - A non-critical `red` never blocks. It is reported among the non-critical failures.

- **Overall status** (the header indicator and the health check app)

  - Computed over the checks whose `status == "finished"`. Unfinished checks are ignored.
  - **Red** when any check is `red`, or when a `critical` check is not `green`.
  - **Yellow** when no rule above applies and any check is not `green`.
  - **Green** when every finished check is `green`.
  - **Gray** is the initial value, before any check has reported.
  - The overall status does **not** carry `critical` (it is already inferred from the tasks).

### Answers to the doubts

1. **“For a task to be considered _failed_, must it be different from `green` and `gray`; that is `red` or `yellow`?”**
   **Yes.** A task is _failed_ when `status == "finished"` and `result` is `red` or `yellow`. Whether that failure stops the server is a separate question, answered by `critical`.

2. **“If `result` is `red`, doesn’t that already imply it’s critical and `critical` is redundant?”**
   **Not anymore.** It used to be true: the only way to reach `red` was to throw from a `critical` task, so `red` implied `critical`. A task now picks its own result, so the two are independent. `result` says how bad the finding is; `critical` says whether that finding stops the server from starting.

   The combination this enables is a non-critical `red`: a serious problem the operator has to see, on a dashboard that still comes up so they can act on it. A certificate that expired is the motivating case — registering that check as critical would lock the operator out of the UI they need to renew it.

### Quick table

| Level          | Possible `result` values         | When is it _failed_?             | Blocks startup?              |
| -------------- | -------------------------------- | -------------------------------- | ---------------------------- |
| Task / Check   | `red`, `yellow`, `green`, `gray` | If `result` is `red` or `yellow` | Only if `critical` and `red` |
| Overall status | `red`, `yellow`, `green`, `gray` | N/A (aggregate state only)       | N/A                          |

### Conclusion:

- A task chooses its own `result`. `yellow` represents a finding that needs attention, `red` a failure.
- `critical` is registration metadata deciding one thing: whether a `red` result blocks the server from starting.
- The two are independent, so a non-critical `red` is reachable and is the reason this distinction exists.

# Notes

- The list of enabled checks are listed in a `info` log in the app logs. This can be used to know the check task names to create a regular expression to filter the enabled checks.

```
server    log   [10:04:59.621] [info][healthcheck] Enabled checks [2]: [server-api:connection-compatibility,index-pattern:alerts,index-pattern:monitoring,index-pattern:statistitcs,index-pattern:vulnerabilities-states,index-pattern:states-inventory,index-pattern:states-inventory-groups,index-pattern:states-inventory-hardware,index-pattern:states-inventory-hotfixes,index-pattern:states-inventory-interfaces,index-pattern:states-inventory-networks,index-pattern:states-inventory-packages,index-pattern:states-inventory-ports,index-pattern:states-inventory-processes,index-pattern:states-inventory-protocols,index-pattern:states-inventory-system,index-pattern:states-inventory-users,index-pattern:states-fim-files,index-pattern:states-fim-registry-keys,index-pattern:states-fim-registry-values]
```

- If the health check is disabled, a `info` log is displayed in the app logs.

# Debug

## Server

The backend service uses a logger tagged as `healthcheck`, so the user can use that keyword to filter the related logs.

```console
journalctl -ru wazuh-dashboard | grep healthcheck
```

The user can increase the verbosity with the `logging.verbose: true` setting.

## Frontend

The UI allows exporting the checks to a JSON file to be shared easily.

- Not ready yet server: export the health check results to a JSON file using the `Export checks` button

```
{
  checks: [
    {
      "name": "server-api:connection-compatibility",
      "status": "finished",
      "result": "green",
      "data": {},
      "createdAt": "2025-08-08T10:04:59.428Z",
      "startedAt": "2025-08-08T10:19:59.858Z",
      "finishedAt": "2025-08-08T10:19:59.948Z",
      "duration": 90,
      "error": null,
      "enabled": true,
      "critical": true,
    }
  ],
  _meta: {
    server: "not_ready"
  }
}
```

- ready server: export the health check results to a JSON file using the health check UI

```
{
  status: "yellow",
  checks: [
    {
      "name": "server-api:connection-compatibility",
      "status": "finished",
      "result": "green",
      "data": {},
      "createdAt": "2025-08-08T10:04:59.428Z",
      "startedAt": "2025-08-08T10:19:59.858Z",
      "finishedAt": "2025-08-08T10:19:59.948Z",
      "duration": 90,
      "error": null,
      "enabled": true,
      "critical": true,
    }
  ],
  _meta: {
    server: "ready"
  }
}
```
