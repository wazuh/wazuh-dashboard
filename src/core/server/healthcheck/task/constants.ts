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
    SUCCESS: 'success',
    WARNING: 'warning',
    FAIL: 'fail',
  },
  CONTEXT: {
    INTERNAL: 'internal',
    USER: 'user',
  },
} as const;
