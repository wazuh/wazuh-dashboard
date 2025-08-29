/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { TaskInfo } from 'src/core/common/healthcheck';

const mapStatusHealth = {
  green: 'success',
  yellow: 'warning',
  red: 'danger',
  gray: 'subdued',
};

export function getHealthFromStatus(status: TaskInfo['result']) {
  return (status && mapStatusHealth[status]) || mapStatusHealth.gray;
}
