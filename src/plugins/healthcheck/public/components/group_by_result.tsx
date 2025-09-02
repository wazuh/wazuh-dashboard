import React from 'react';
import { EuiAccordion, EuiCallOut, EuiFlexGroup, EuiFlexItem, EuiText } from '@elastic/eui';
import { FormattedMessage } from '@osd/i18n/react';
import { TaskInfo } from 'src/core/common/healthcheck';
import { getHealthFromStatus } from './services/health';
import { formatDate } from './services/time';
import { getCore } from '../dashboards_services';
import { CheckDetails } from './check_details';

interface GroupByResultProps {
  result: 'green' | 'yellow' | 'red';
  checks: TaskInfo[];
}

export const GroupByResult = ({ result, checks }: GroupByResultProps) => {
  const core = getCore();

  const buttonContent = (
    <EuiText size="s" color={getHealthFromStatus(result)}>
      <FormattedMessage
        id="healthcheck.groupByResult"
        defaultMessage="Check with result: {result}"
        values={{ result }}
      />
    </EuiText>
  );

  const accordion = (
    <EuiAccordion id="groupByResult" buttonContent={buttonContent}>
      <EuiFlexGroup direction="column">
        {checks.map((check, index) => (
          <EuiFlexItem key={index}>
            <CheckDetails
              check={check}
              formatDate={(date: string) => formatDate(core.uiSettings, date)}
            />
          </EuiFlexItem>
        ))}
      </EuiFlexGroup>
    </EuiAccordion>
  );

  return <EuiCallOut title={accordion} color={getHealthFromStatus(result)} />;
};
