/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { FunctionComponent, useEffect, useState } from 'react';
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
          value: TASK.RUN_RESULT.GREEN,
          name:
            TASK.RUN_RESULT.GREEN.charAt(0).toUpperCase() +
            TASK.RUN_RESULT.GREEN.slice(1).toLowerCase(),
        },
        {
          value: TASK.RUN_RESULT.YELLOW,
          name:
            TASK.RUN_RESULT.YELLOW.charAt(0).toUpperCase() +
            TASK.RUN_RESULT.YELLOW.slice(1).toLowerCase(),
        },
        {
          value: TASK.RUN_RESULT.RED,
          name:
            TASK.RUN_RESULT.RED.charAt(0).toUpperCase() +
            TASK.RUN_RESULT.RED.slice(1).toLowerCase(),
        },
        {
          value: TASK.RUN_RESULT.GRAY,
          name:
            TASK.RUN_RESULT.GRAY.charAt(0).toUpperCase() +
            TASK.RUN_RESULT.GRAY.slice(1).toLowerCase(),
        },
      ],
    },
    {
      type: 'field_value_toggle_group',
      field: '_meta.isCritical',
      items: [
        { name: 'Critical', value: true },
        { name: 'Non-critical', value: false },
      ],
    },
    {
      type: 'field_value_toggle_group',
      field: '_meta.isEnabled',
      items: [
        { name: 'Enabled', value: true },
        { name: 'Disabled', value: false },
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
