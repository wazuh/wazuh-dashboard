import React from 'react';
import { EuiBadge, EuiBasicTableProps, EuiButtonIcon, EuiText } from '@elastic/eui';
import { i18n } from '@osd/i18n';
import { TaskInfo } from '../../../../../core/common/healthcheck';
import { getHealthFromStatus } from '../services/health';
import { Result } from '../../constants';

const renderStatus = (result: Result) => {
  const health = getHealthFromStatus(result);

  return <EuiBadge color={health}>{result}</EuiBadge>;
};

export const tableColumns = (
  openFlyout: (item?: TaskInfo<{ isCritical: boolean; isEnabled: boolean }> | null) => void
): EuiBasicTableProps<TaskInfo>['columns'] => [
  {
    render: (item: TaskInfo<{ isCritical: boolean; isEnabled: boolean }>) => (
      <EuiButtonIcon
        iconType="inspect"
        aria-label="View details"
        onClick={() => openFlyout(item)}
      />
    ),
    width: '32px',
  },
  {
    field: 'name',
    name: i18n.translate('healthcheck.statusPage.statusTable.columns.nameHeader', {
      defaultMessage: 'Check',
    }),
    render: (name: string) => {
      const [type, check] = name.split(':');

      return (
        <EuiText>
          {type}:<strong>{check}</strong>
        </EuiText>
      );
    },
    width: '450px',
    truncateText: true,
  },
  {
    field: 'result',
    name: i18n.translate('healthcheck.statusPage.statusTable.columns.resultHeader', {
      defaultMessage: 'Result',
    }),
    width: '100px',
    render: (result: string) => renderStatus(result as Result),
  },
  {
    field: 'status',
    name: i18n.translate('healthcheck.statusPage.statusTable.columns.statusHeader', {
      defaultMessage: 'Status',
    }),
    width: '150px',
  },
  {
    field: 'error',
    name: i18n.translate('healthcheck.statusPage.statusTable.columns.errorHeader', {
      defaultMessage: 'Error',
    }),
    truncateText: true,
    render: (error: string) => {
      if (!error) {
        return 'Is healthy';
      }
      return (
        <>
          <span className="eui-textTruncate">{error}</span>
        </>
      );
    },
  },
];
