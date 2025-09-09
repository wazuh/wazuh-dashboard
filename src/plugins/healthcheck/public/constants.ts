/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { i18n } from '@osd/i18n';

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
  green: i18n.translate('healthcheck.status.green', {
    defaultMessage:
      'Status: green. This indicates that the verification has been performed correctly.',
  }),
  yellow: i18n.translate('healthcheck.status.yellow', {
    defaultMessage:
      'Status: yellow. This indicates that the verification had some problem but it could work.',
  }),
  red: i18n.translate('healthcheck.status.red', {
    defaultMessage: 'Status: red. This indicates that the verification had some error.',
  }),
  gray: i18n.translate('healthcheck.status.gray', {
    defaultMessage: 'Status: gray. This indicates that the verification has been disabled.',
  }),
  null: i18n.translate('healthcheck.status.null', {
    defaultMessage: 'Status: null. This indicates that the verification has not been performed.',
  }),
};

export const STATUS_CHECK_EXPLAIN = {
  green: i18n.translate('healthcheck.statusCheck.green', {
    defaultMessage: 'The check has been successfully completed.',
  }),
  yellow: i18n.translate('healthcheck.statusCheck.yellow', {
    defaultMessage:
      'The check is non-critical and has failed. You can continue using the system but some features may be unavailable.',
  }),
  red: i18n.translate('healthcheck.statusCheck.red', {
    defaultMessage:
      'The check is critical and has failed. You should take action to resolve this issue.',
  }),
  gray: i18n.translate('healthcheck.statusCheck.gray', {
    defaultMessage: 'The check is disabled.',
  }),
  null: i18n.translate('healthcheck.statusCheck.null', {
    defaultMessage: 'The check has not been run yet.',
  }),
};
