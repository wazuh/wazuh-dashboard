/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { FunctionComponent, useEffect, useState } from 'react';
import { i18n } from '@osd/i18n';
import { EuiBasicTable, EuiSearchBar, EuiSearchBarProps } from '@elastic/eui';
import { isEqual } from 'lodash';
import { TaskInfo } from '../../../../../core/common/healthcheck';
import { CheckFlyout } from './check_flyout';
import { getCore } from '../../dashboards_services';
import { formatDate } from '../services/time';
import { tableColumns } from './columns';
import { TASK } from '../../constants';

interface ChecksTableProps {
  checks: Array<TaskInfo<{ isCritical: boolean; isEnabled: boolean }>>;
}

const initialQuery = EuiSearchBar.Query.MATCH_ALL;

export const ChecksTable: FunctionComponent<ChecksTableProps> = ({ checks }) => {
  const [flyoutVisible, setFlyoutVisible] = useState(false);
  const [check, setCheck] = useState<TaskInfo<{ isCritical: boolean; isEnabled: boolean }> | null>(
    null
  );
  const [query, setQuery] = useState(initialQuery);
  const [filteredChecks, setFilteredChecks] = useState(checks);

  const core = getCore();

  useEffect(() => {
    const queriedItems = EuiSearchBar.Query.execute(query, checks);
    setFilteredChecks(queriedItems);
  }, [query, checks]);

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

  const onChangeQuery = ({ query: searchQuery }) => {
    setQuery(searchQuery);
  };

  const filters: EuiSearchBarProps['filters'] = [
    {
      type: 'field_value_toggle_group',
      field: 'result',
      items: [
        {
          value: TASK.RUN_RESULT.GREEN.value,
          name: TASK.RUN_RESULT.GREEN.label,
        },
        {
          value: TASK.RUN_RESULT.YELLOW.value,
          name: TASK.RUN_RESULT.YELLOW.label,
        },
        {
          value: TASK.RUN_RESULT.RED.value,
          name: TASK.RUN_RESULT.RED.label,
        },
      ],
    },
    {
      type: 'field_value_toggle_group',
      field: '_meta.isEnabled',
      items: [
        { name: i18n.translate('healthcheck.enabled', { defaultMessage: 'Enabled' }), value: true },
        {
          name: i18n.translate('healthcheck.disabled', { defaultMessage: 'Disabled' }),
          value: false,
        },
      ],
    },
  ];

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
      <EuiSearchBar defaultQuery={initialQuery} onChange={onChangeQuery} filters={filters} />
      <EuiBasicTable
        columns={tableColumns(openFlyout)}
        items={filteredChecks}
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
