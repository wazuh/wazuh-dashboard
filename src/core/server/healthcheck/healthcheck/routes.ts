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

export function addRoutes(router, { healthcheck, logger }) {
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

  // Get the status of internal initialization tasks
  router.get(
    {
      path: '/internal',
      validate: {
        tasks: schema.object({
          tasks: validateTaskList,
        }),
      },
    },
    async (context, request, response) => {
      try {
        const tasksNames = request.query.tasks ? getTaskList(request.query.tasks) : undefined;

        logger.debug(`Getting initialization tasks related to internal scope`);

        const tasksData = healthcheck.getChecksInfo(tasksNames);

        logger.debug(
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
  );

  // Run the internal initialization tasks
  // TODO: protect with administrator privilegies
  router.post(
    {
      path: '/internal',
      validate: {
        query: schema.maybe(
          schema.object({
            tasks: validateTaskList,
          })
        ),
      },
    },
    async (context, request, response) => {
      try {
        logger.debug(`Running healthcheck tasks related to internal scope`);
        const tasksNames = request.query.tasks ? getTaskList(request.query.tasks) : undefined;

        const results = await healthcheck.runInternal(tasksNames);

        logger.info('Healthcheck tasks related to internal scope were executed');

        return response.ok({
          body: {
            message: 'All healthcheck tasks are returned.',
            tasks: results?.checks,
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
  );

  router.post(
    {
      path: '/user',
      validate: {
        // TODO: restrict to user tasks
        query: schema.object({
          tasks: validateTaskList,
        }),
      },
    },
    async (context, request, response) => {
      try {
        const tasksNames = request.query.tasks ? getTaskList(request.query.tasks) : undefined;
        const { username } = await context.wazuh_core.dashboardSecurity.getCurrentUser(
          request,
          context
        );
        const scope = 'user';

        logger.debug(`Getting healthcheck tasks related to user [${username}] scope [${scope}]`);

        const initializationTasks = context.wazuh_core.initialization.get();
        const indexPatternTasks = initializationTasks
          .filter(({ name }) => name.startsWith('index-pattern:'))
          .map(({ name }) =>
            context.wazuh_core.initialization.createNewTaskFromRegisteredTask(name)
          );
        const settingsTasks = initializationTasks
          .filter(({ name }) => name.startsWith('setting:'))
          .map(({ name }) =>
            context.wazuh_core.initialization.createNewTaskFromRegisteredTask(name)
          );
        const allUserTasks = [...indexPatternTasks, ...settingsTasks];
        const tasks = tasksNames
          ? allUserTasks.filter(({ name }) => tasksNames.includes(name))
          : allUserTasks;

        logger.debug(
          `Initialization tasks related to user [${username}] scope [${scope}]: [${tasks
            .map(({ name }) => name)
            .join(', ')}]`
        );

        const taskContext = context.wazuh_core.initialization.createRunContext('user', {
          core: context.core,
          request,
        });

        logger.debug(`Running tasks for user [${username}] scope [${scope}]`);

        const results = await Promise.all(
          tasks.map(async (task) => {
            const taskLogger = enhanceTaskLogger(logger);

            try {
              await task.run({
                ...taskContext,
                // TODO: use user selection index patterns
                logger: taskLogger,
                ...(task.name.includes('index-pattern:')
                  ? {
                      getIndexPatternID: () =>
                        task.name /* TODO: use request parameters/body/cookies */,
                    }
                  : {}),
              });
            } catch {
              /* empty */
            } finally {
              // eslint-disable-next-line no-unsafe-finally
              return {
                logs: taskLogger.getLogs(),
                ...task.getInfo(),
              };
            }
          })
        );

        logger.debug(`All tasks for user [${username}] scope [${scope}] run`);

        const initialMessage = 'All the initialization tasks related to user scope were executed.';
        const message = [
          initialMessage,
          results.some(({ error }) => error) && 'There was some errors.',
        ]
          .filter(Boolean)
          .join(' ');

        return response.ok({
          body: {
            message,
            tasks: results,
          },
        });
      } catch (error) {
        return response.internalError({
          body: {
            message: `Error initializating the tasks: ${error.message}`,
          },
        });
      }
    }
  );
}
