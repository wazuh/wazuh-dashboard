/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { EuiHealth, EuiToolTip } from '@elastic/eui';
import { FormattedMessage } from 'react-intl';
import { HealthCheckStatus } from '../types';
import { getHealthFromStatus } from './services/health';

const statusChecksExplain = {
  green: (
    <FormattedMessage
      id="core.healthcheck.status_info.green"
      defaultMessage="Status: green. This indicates that the verification has been performed correctly."
    />
  ),
  yellow: (
    <FormattedMessage
      id="core.healthcheck.status_info.yellow"
      defaultMessage="Status: yellow. This indicates that the verification had some problem but it could work."
    />
  ),
  red: (
    <FormattedMessage
      id="core.healthcheck.status_info.red"
      defaultMessage="Status: red. This indicates that the verification had some error."
    />
  ),
  gray: (
    <FormattedMessage
      id="core.healthcheck.status_info.gray"
      defaultMessage="Status: gray. This indicates that the verification has been disabled."
    />
  ),
};

export const HealthIcon = ({
  children,
  tooltip,
  status,
}: {
  children?: React.node;
  tooltip?: React.node;
  status: HealthCheckStatus['status'];
}) => (
  <EuiToolTip content={tooltip || statusChecksExplain[status]} position="bottom">
    <EuiHealth color={getHealthFromStatus(status)}>{children}</EuiHealth>
  </EuiToolTip>
);
