# HealthCheck

The `HealthCheck` provides a mechanism to register and run tasks when the app runs.

This is exposed throught the initialization service of core.

Other plugins can register tasks in the plugin `setup` lifecycle that will be run on the server starts lifecycle.

Optionally the registered tasks could be retrieved to run in API endpoints or getting information about its status.

There are 2 scopes:

- `internal`: run through the internal user
  - on plugin starts
  - on demand
- `user`: run through the logged (requester) user
  - on demand

The scopes can be used to get a specific context (clients, parameters) that is set in the `scope` property of the task context.

The `internal` scoped tasks keep the same execution data (see [Task execution data](#task-execution-data)), and the `user` scoped task are newly created on demand.

When the app starts, all the registered tasks run for the `internal` scope and should pass to swap the server to the "final" server, else
accessing to the app will display the `Wazuh dashboard server is not ready yet` view and optionally list the errors in the tasks. This blocks
set the final server until all the checks are ok.

# HealthCheck tasks

A task can be defined with:

```ts
interface InitializationTaskDefinition {
  name: string;
  run: (ctx: any) => any;
  order?: number
  isCritical: boolean
}
```

The `name` is used to identify the task and this is rendered in the context logger.

The `order` defines the order to execute the task. Multiple tasks can have the same order and will be executed in parallel. If it is not defined, the task will be executed as last order group.

The `isCritical` defines on any error, the health check should be considered as failed.

The `ctx` is the context of the task execution and includes core services and task context services or dependencies.

For example, in the server log:

```
server    log   [11:57:39.648] [info][index-pattern-vulnerabilities-states][healthcheck][plugins][wazuhCore] Index pattern with ID [wazuh-states-vulnerabilities-*] does not exist

```

the task name is `index-pattern-vulnerabilities-states`.

## Task name convention

- lowercase
- kebab case (`word1-word2`)
- use colon ( `:` ) for tasks related to some entity that have different subentities.

```
entity_identifier:entity_specific
```

For example:

```
index-pattern:alerts
index-pattern:statistics
index-pattern:vulnerabilities-states
```

## Register a task

```ts
// plugin setup
setup(){

  // Register a task
  core.healthcheck.register({
    name: 'custom-task',
    run: (ctx) => {
      console.log('Run from wazuhCore starts' )
    },
    order: 1
    isCritical: false
  });
}
```

## Task execution data

The task has the following data related to the execution:

```ts
interface InitializationTaskRunData {
  name: string;
  status: 'not_started' | 'running' | 'finished';
  result: 'success' | 'fail';
  createdAt: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  duration: number | null; // seconds
  data: any;
  error: string | null;
  _meta: any
}
```

## Create a task instance

This is used to create the user scoped tasks.

```ts
const newTask =
  core.healthcheck.createNewTaskFromRegisteredTask(
    'example-task',
  );
```

## Context

### Internal

```ts
interface {
  services: {
  },
  context: {
    services: {
      core: CoreStartServices
    },
    logger: Logger,
    scope: 'internal'
  }
}
```

### User

```ts
TBD
interface {
  services: {
  },
  context: {
    services: {
      core: CoreStartServices
    },
    context: RequestHandlerContext,
    request: OpenSearchDashboardsRequest
    logger: Logger,
    scope: 'user'
  }
}
```