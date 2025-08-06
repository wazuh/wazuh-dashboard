/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { schema } from '@osd/config-schema';

const getTaskList = (tasksAsString: string) => tasksAsString.split(',');

interface EnhancedLoggerLog {
  timestamp: string;
  level: string;
  message: string;
}

function enhanceTaskLogger(logger) {
  const logs: EnhancedLoggerLog[] = [];
  const enhancedLogger = {
    getLogs() {
      return logs;
    },
  };

  for (const level of ['debug', 'info', 'warn', 'error']) {
    enhancedLogger[level] = (message: string) => {
      logs.push({ timestamp: new Date().toISOString(), level, message });
      logger[level](message);
    };
  }

  return enhancedLogger;
}

function createAdapterHandler(fn) {
  return function (request, h) {
    const context = {};
    const response = {
      ok: ({ body }) => {
        return h.response(body).type('application/json').code(200);
      },
      badRequest: ({ body }) => {
        return h.response(body).type('application/json').code(400);
      },
      internalError: ({ body }) => {
        return h.response(body).type('application/json').code(503);
      },
    };
    return fn(context, request, response);
  };
}

function validateRoute(validation) {
  return function (fn) {
    return function (...args) {
      const [_, request, response] = args;
      if (validation && validation.query) {
        try {
          validation.query.validate(request.query);
        } catch (err) {
          return response.badRequest({ body: { error: err.message } });
        }
      }
      return fn(...args);
    };
  };
}

async function handlerGetConfig(_context, _request, response) {
  try {
    this.logger.debug('Getting health check config');

    return response.ok({
      body: this.healthcheck.getConfig(),
    });
  } catch (error) {
    return response.internalError({
      body: {
        message: `Error getting the health check config: ${error.message}`,
      },
    });
  }
}

async function handlerGetTasks(_context, request, response) {
  try {
    const tasksNames = request.query.name ? getTaskList(request.query.name) : undefined;

    this.logger.debug(`Getting health check tasks related to internal scope`);

    const tasksData = this.healthcheck.getChecksInfo(tasksNames);

    this.logger.debug(
      `Healthcheck tasks related to internal scope: [${[...tasksData]
        .map(({ name }) => name)
        .join(', ')}]`
    );

    return response.ok({
      body: {
        message: 'All healthcheck tasks are returned.',
        tasks: tasksData,
      },
    });
  } catch (error) {
    return response.internalError({
      body: {
        message: `Error getting the internal healthcheck tasks: ${error.message}`,
      },
    });
  }
}

async function handlerRunTasks(_context, request, response) {
  try {
    this.logger.debug(`Running healthcheck tasks related to internal scope`);
    const tasksNames = request.query.name ? getTaskList(request.query.name) : undefined;

    let tasks;
    try {
      const results = await this.healthcheck.runInternal(tasksNames);
      tasks = results.checks;
    } catch (err) {
      tasks = this.healthcheck.getChecksInfo(tasksNames);
    }

    this.logger.info('Healthcheck tasks related to internal scope were executed');

    return response.ok({
      body: {
        message: 'All healthcheck tasks are returned.',
        tasks,
      },
    });
  } catch (error) {
    return response.internalError({
      body: {
        message: `Error running the internal healthcheck tasks: ${error.message}`,
      },
    });
  }
}

export function addRoutesReadyServer(router, { healthcheck, logger }) {
  const validateTaskList = schema.maybe(
    schema.string({
      validate(value: string) {
        const tasks = healthcheck.getAll();
        const requestTasks = getTaskList(value);
        const invalidTasks = requestTasks.filter((requestTask) =>
          tasks.every(({ name }) => requestTask !== name)
        );

        if (invalidTasks.length > 0) {
          return `Invalid tasks: ${invalidTasks.join(', ')}`;
        }

        return undefined;
      },
    })
  );

  // Get configuration
  router.get(
    {
      path: '/config',
      validate: false,
    },
    handlerGetConfig.bind({ healthcheck, logger })
  );

  // Get the status of internal health check tasks
  router.get(
    {
      path: '/internal',
      validate: {
        query: schema.maybe(
          schema.object({
            name: validateTaskList,
          })
        ),
      },
    },
    handlerGetTasks.bind({ healthcheck, logger })
  );

  // Run the internal health check tasks
  router.post(
    {
      path: '/internal',
      validate: {
        query: schema.maybe(
          schema.object({
            name: validateTaskList,
          })
        ),
      },
    },
    handlerRunTasks.bind({ healthcheck, logger })
  );
}

// Routers not-ready server
export function addRoutesNotReadyServer(server, { healthcheck, logger }) {
  const validateTaskList = schema.maybe(
    schema.string({
      validate(value: string) {
        const tasks = healthcheck.getAll();
        const requestTasks = getTaskList(value);
        const invalidTasks = requestTasks.filter((requestTask) =>
          tasks.every(({ name }) => requestTask !== name)
        );

        if (invalidTasks.length > 0) {
          return `Invalid tasks: ${invalidTasks.join(', ')}`;
        }

        return;
      },
    })
  );

  // Get configuration
  server.route({
    path: '/api/healthcheck/config',
    method: 'get',
    handler: createAdapterHandler(handlerGetConfig.bind({ healthcheck, logger })),
  });

  // Get the status of internal health check tasks
  server.route({
    path: '/api/healthcheck/internal',
    method: 'get',
    handler: createAdapterHandler(
      validateRoute({
        query: schema.maybe(
          schema.object({
            name: validateTaskList,
          })
        ),
      })(handlerGetTasks.bind({ healthcheck, logger }))
    ),
  });

  // // Run the internal health check tasks
  server.route({
    path: '/api/healthcheck/internal',
    method: 'post',
    handler: createAdapterHandler(handlerRunTasks.bind({ healthcheck, logger })),
  });
}
