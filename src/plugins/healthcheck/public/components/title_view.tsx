/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { EuiText } from '@elastic/eui';
import { FormattedMessage } from 'react-intl';
import { groupBy } from 'lodash';
import { TASK, RESULT } from '../constants';
import { HealthIcon } from './health_icon';
import { TaskInfo } from '../../../../core/common/healthcheck';
import { BadgeResults } from './utils/badge_results';

interface TitleViewProps {
  status: RESULT;
  checks: Array<TaskInfo<{ isCritical: boolean; isEnabled: boolean }>>;
}

export const TitleView = ({ status, checks }: TitleViewProps) => {
  const checksGroupByResult = groupBy(checks, 'result');

  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'right' }}>
      <EuiText>
        <h3>
          <FormattedMessage id="healthcheck.statusTitle" defaultMessage="Status is " />
          <BadgeResults result={status} />
        </h3>
      </EuiText>
      <div style={{ marginLeft: '4px' }}>
        {[
          TASK.RUN_RESULT.GREEN,
          TASK.RUN_RESULT.YELLOW,
          TASK.RUN_RESULT.RED,
          TASK.RUN_RESULT.GRAY,
        ].map((result) => {
          const CheckByResult = checksGroupByResult?.[result]?.length ?? 0;
          if (CheckByResult > 0) {
            return (
              <HealthIcon key={result} status={result}>
                {CheckByResult}
              </HealthIcon>
            );
          }
          return null;
        })}
      </div>
    </div>
  );
};
