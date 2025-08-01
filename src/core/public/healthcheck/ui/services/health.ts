/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

const mapStatusHealth = {
  green: 'success',
  yellow: 'warning',
  red: 'danger',
  gray: 'subdued',
};

export function getHealthFromStatus(status: string) {
  return mapStatusHealth[status] || mapStatusHealth.gray;
}
