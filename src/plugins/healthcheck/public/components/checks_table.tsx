/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * The OpenSearch Contributors require contributions made to
 * this file be licensed under the Apache-2.0 license or a
 * compatible open source license.
 *
 * Any modifications Copyright OpenSearch Contributors. See
 * GitHub history for details.
 */

/*
 * Licensed to Elasticsearch B.V. under one or more contributor
 * license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright
 * ownership. Elasticsearch B.V. licenses this file to you under
 * the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import React, { FunctionComponent, useState } from 'react';
import { EuiBadge, EuiBasicTable, EuiBasicTableProps, EuiButtonIcon, EuiText } from '@elastic/eui';
import { i18n } from '@osd/i18n';
import { isEqual } from 'lodash';
import { TaskInfo } from '../../../../core/common/healthcheck';
import { getHealthFromStatus } from './services/health';
import { CheckFlyout } from './check_flyout';
import { getCore } from '../dashboards_services';
import { formatDate } from './services/time';

interface ChecksTableProps {
  checks: TaskInfo[];
}

type Result = 'green' | 'yellow' | 'red' | 'gray';

const renderStatus = (result: Result, isCritical: boolean) => {
  const health = getHealthFromStatus(result);

  const labels = {
    danger: i18n.translate('healthcheck.statusPage.statusTable.columns.status.danger', {
      defaultMessage: 'Critical',
    }),
    warning: i18n.translate('healthcheck.statusPage.statusTable.columns.status.warning', {
      defaultMessage: 'Warning',
    }),
    success: i18n.translate('healthcheck.statusPage.statusTable.columns.status.success', {
      defaultMessage: 'Healthy',
    }),
  };

  return <EuiBadge color={health}>{labels[health as keyof typeof labels]}</EuiBadge>;
};

const tableColumns = (
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
          {type}: <strong>{check}</strong>
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
    render: (result: string, item: TaskInfo<{ isCritical: boolean }>) =>
      renderStatus(result as Result, item._meta.isCritical),
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

export const ChecksTable: FunctionComponent<ChecksTableProps> = ({ checks }) => {
  const [flyoutVisible, setFlyoutVisible] = useState(false);
  const [check, setCheck] = useState<TaskInfo | null>(null);

  const core = getCore();

  const openFlyout = (item?: TaskInfo<{ isCritical: boolean; isEnabled: boolean }> | null) => {
    if (!item) {
      setFlyoutVisible(false);
      setCheck(null);
    }

    if (isEqual(item, check)) {
      setFlyoutVisible(false);
      setCheck(null);
    } else {
      setFlyoutVisible(true);
      setCheck(item);
    }
  };

  const getCellProps = (item: any, column: any) => {
    const { id } = item;
    const { field } = column;
    return {
      'data-test-subj': `cell-${id}-${field}`,
      textOnly: true,
    };
  };

  return (
    <>
      <EuiBasicTable
        columns={tableColumns(openFlyout)}
        items={checks}
        tableLayout="fixed"
        cellProps={getCellProps}
      />
      {flyoutVisible && check && (
        <CheckFlyout
          check={check}
          formatDate={(date) => formatDate(core.uiSettings, date)}
          setIsFlyoutVisible={setFlyoutVisible}
        />
      )}
    </>
  );
};
