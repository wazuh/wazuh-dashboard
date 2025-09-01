/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import {
  EuiButtonEmpty,
  EuiToolTip,
  EuiPopover,
  EuiContextMenuPanel,
  EuiFlexGroup,
  EuiFlexItem,
  EuiCheckbox,
  EuiHorizontalRule,
  EuiText,
  EuiIcon,
} from '@elastic/eui';
import { FormattedMessage } from '@osd/i18n/react';
import { get } from 'lodash';
import { TASK } from '../constants';
import { HealthIcon } from './health_icon';

function propEquals(propPath: string, expectedValue: any) {
  return function (obj: any) {
    return get(obj, propPath) === expectedValue;
  };
}

export const checkFilters = {
  'enabled:yes': propEquals('_meta.isEnabled', true),
  'enabled:no': propEquals('_meta.isEnabled', false),
  'result:green': propEquals('result', TASK.RUN_RESULT.GREEN),
  'result:yellow': propEquals('result', TASK.RUN_RESULT.YELLOW),
  'result:red': propEquals('result', TASK.RUN_RESULT.RED),
  'result:gray': propEquals('result', TASK.RUN_RESULT.GRAY),
  'critical:yes': propEquals('_meta.isCritical', true),
  'critical:no': propEquals('_meta.isCritical', false),
};

export type CheckFilters = keyof typeof checkFilters;

const availableFiltersCategories = [
  {
    label: 'Enabled',
    id: 'enabled',
    filters: [
      { label: 'yes', id: 'enabled:yes' },
      { label: 'no', id: 'enabled:no' },
    ],
  },
  {
    label: 'Result',
    id: 'result',
    filters: [
      {
        label: <HealthIcon status={TASK.RUN_RESULT.GREEN} />,
        id: 'result:green',
      },
      {
        label: <HealthIcon status={TASK.RUN_RESULT.YELLOW} />,
        id: 'result:yellow',
      },
      {
        label: <HealthIcon status={TASK.RUN_RESULT.RED} />,
        id: 'result:red',
      },
      {
        label: <HealthIcon status={TASK.RUN_RESULT.GRAY} />,
        id: 'result:gray',
      },
    ],
  },
  {
    label: 'Critical',
    id: 'critical',
    filters: [
      { label: 'yes', id: 'critical:yes' },
      { label: 'no', id: 'critical:no' },
    ],
  },
];

export const ButtonFilterChecksCheck = ({
  filters,
  setFilters,
}: {
  filters: Array<{ id: CheckFilters }>;
  setFilters: (fn: (state: Array<{ id: CheckFilters }>) => Array<{ id: CheckFilters }>) => void;
}) => {
  const [isPopoverOpen, setIsPopoverOpen] = useState(false);
  const button = (
    <EuiToolTip
      content={
        filters?.length ? (
          <FormattedMessage
            id="healthcheck.filter.tooltip_has_applied_filters"
            defaultMessage="Filter visible checks. There are applied filters."
          />
        ) : (
          <FormattedMessage
            id="healthcheck.filter.tooltip"
            defaultMessage="Filter visible checks"
          />
        )
      }
      position="bottom"
    >
      <EuiButtonEmpty
        iconType="filter"
        onClick={() => setIsPopoverOpen((state) => !state)}
        aria-label="Filter visible checks"
        isSelected={isPopoverOpen}
        color={filters?.length ? 'warning' : 'primary'}
      >
        Filter
      </EuiButtonEmpty>
    </EuiToolTip>
  );
  return (
    <EuiPopover
      data-test-subj="account-popover"
      id="healthcheckVisibleChecks"
      button={button}
      isOpen={isPopoverOpen}
      closePopover={() => {
        setIsPopoverOpen(false);
      }}
      panelPaddingSize="s"
    >
      <EuiContextMenuPanel>
        <EuiFlexGroup responsive={false}>
          <EuiFlexItem>
            <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
              <EuiText>
                <h3>
                  <FormattedMessage id="healthcheck.filter.title" defaultMessage="Filters" />
                </h3>
              </EuiText>
              <EuiToolTip
                content={
                  <FormattedMessage
                    id="healthcheck.filter.title.tooltip"
                    defaultMessage="If any selected filter matches with the check, this will be filtered. This only affects to the visible checks."
                  />
                }
                position="bottom"
              >
                <EuiIcon type="iInCircle" aria-label="Filters tooltip" />
              </EuiToolTip>
            </div>
          </EuiFlexItem>
        </EuiFlexGroup>
        <EuiHorizontalRule margin="xs" />
        {availableFiltersCategories.map(
          ({ label: categoryLabel, id: categoryId, filters: filtersByCategory }) => {
            return (
              <EuiFlexGroup
                responsive={false}
                key={categoryId}
                alignItems="center"
                justifyContent="spaceBetween"
              >
                <EuiFlexItem>{categoryLabel}</EuiFlexItem>
                <EuiFlexItem grow={false}>
                  <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '4px' }}>
                    {filtersByCategory.map((availableFilter) => {
                      return (
                        <EuiCheckbox
                          key={`${categoryId}:${availableFilter.id}`}
                          id={availableFilter.id}
                          label={availableFilter.label}
                          checked={Boolean(
                            filters.find(
                              ({ id }: { id: CheckFilters }) => id === availableFilter.id
                            )
                          )}
                          onChange={(e) => {
                            const value = e.target.checked;
                            setFilters((state: Array<{ id: CheckFilters }>) => {
                              return [
                                ...state.filter(
                                  ({ id }: { id: CheckFilters }) => id !== availableFilter.id
                                ),
                                ...(value ? [{ id: availableFilter.id }] : []),
                              ] as Array<{ id: CheckFilters }>;
                            });
                          }}
                        />
                      );
                    })}
                  </div>
                </EuiFlexItem>
              </EuiFlexGroup>
            );
          }
        )}
      </EuiContextMenuPanel>
    </EuiPopover>
  );
};
