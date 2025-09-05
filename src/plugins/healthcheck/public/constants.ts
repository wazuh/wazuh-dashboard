/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import wazuh from '../../../../package.json';

export const WAZUH_MAJOR = wazuh.wazuh.version.split('.')[0];
export const WAZUH_MINOR = wazuh.wazuh.version.split('.')[1];

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

export type Result = 'green' | 'yellow' | 'red' | 'gray';

export const STATUS_CHECKS_EXPLAIN = {
  green: 'Status: green. This indicates that the verification has been performed correctly.',
  yellow:
    'Status: yellow. This indicates that the verification had some problem but it could work.',
  red: 'Status: red. This indicates that the verification had some error.',
  gray: 'Status: gray. This indicates that the verification has been disabled.',
  null: 'Status: gray. This indicates that the verification has been disabled.',
};
