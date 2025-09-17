/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

export const TASK = {
  RUN_STATUS: {
    NOT_STARTED: 'not_started',
    RUNNING: 'running',
    FINISHED: 'finished',
  },
  RUN_RESULT: {
    NULL: null,
    GRAY: 'gray',
    GREEN: 'green',
    YELLOW: 'yellow',
    RED: 'red',
  },
  CONTEXT: {
    INTERNAL: 'internal',
    USER: 'user',
  },
} as const;
