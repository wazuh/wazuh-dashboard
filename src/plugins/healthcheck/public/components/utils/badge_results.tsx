/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { EuiBadge, EuiToolTip } from '@elastic/eui';
import { getHealthFromStatus } from '../services/health';
import { RESULT, STATUS_CHECK_EXPLAIN } from '../../constants';

interface BadgeResultsProps {
  result: RESULT;
}

export const BadgeResults = ({ result }: BadgeResultsProps) => {
  const health = getHealthFromStatus(result);

  return (
    <EuiToolTip content={STATUS_CHECK_EXPLAIN[result]}>
      <EuiBadge color={health}>{result}</EuiBadge>
    </EuiToolTip>
  );
};
