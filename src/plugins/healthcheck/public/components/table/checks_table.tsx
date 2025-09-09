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
  checks: TaskInfo[];
}

const initialQuery = EuiSearchBar.Query.MATCH_ALL;

export const ChecksTable: FunctionComponent<ChecksTableProps> = ({ checks }) => {
  const [flyoutVisible, setFlyoutVisible] = useState(false);
  const [check, setCheck] = useState<TaskInfo | null>(null);
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
