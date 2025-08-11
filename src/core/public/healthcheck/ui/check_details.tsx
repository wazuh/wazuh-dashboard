/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */
import React, { useState } from 'react';
import { EuiButtonIcon, EuiFlexGroup, EuiFlexItem, EuiText, EuiToolTip } from '@elastic/eui';
import { FormattedMessage } from 'react-intl';
import { TaskInfo } from 'src/core/common/healthcheck';
import { HealthIcon } from './health_icon';
import { useAsyncAction } from './hook/use_async_action';

interface CheckDetailsProps {
  check: TaskInfo;
  run: () => Promise<void>;
  formatDate: (date: string) => string;
}

export const CheckDetails = ({ check, run, formatDate }: CheckDetailsProps) => {
  const { name, duration, startedAt, finishedAt, error, _meta } = check;
  const [detailsIsOpen, setDetailsIsOpen] = useState<boolean>(false);
  const runAction = useAsyncAction(run);

  let nameCheck = (
    <EuiText color={_meta?.isEnabled ? 'default' : 'subdued'} size="s">
      {name}
    </EuiText>
  );

  if (!_meta?.isEnabled) {
    nameCheck = (
      <EuiToolTip
        content={
          <FormattedMessage
            id="core.healthcheck.status.disabledExplain"
            defaultMessage="Disabled. This does not run on initial or scheduled executions."
          />
        }
        position="bottom"
      >
        {nameCheck}
      </EuiToolTip>
    );
  }
  return (
    <>
      <EuiFlexGroup justifyContent="spaceBetween" responsive={false}>
        <EuiFlexItem grow={false}>
          <div style={{ display: 'flex' }}>
            <HealthIcon status={check.result} />
            {nameCheck}
          </div>
        </EuiFlexItem>
        <EuiFlexItem grow={false}>
          <div style={{ display: 'flex' }}>
            <EuiToolTip
              content={
                <FormattedMessage
                  id="core.healthcheck.check.view_details"
                  defaultMessage="View details"
                />
              }
              position="bottom"
            >
              <EuiButtonIcon
                iconType="iInCircle"
                onClick={() => setDetailsIsOpen((state) => !state)}
                aria-label="View details"
              />
            </EuiToolTip>

            <EuiToolTip
              content={
                <FormattedMessage id="core.healthcheck.check.run" defaultMessage="Run check" />
              }
              position="bottom"
            >
              <EuiButtonIcon
                iconType="refresh"
                onClick={runAction.run}
                isDisabled={runAction.running}
                aria-label="Run check"
              />
            </EuiToolTip>
          </div>
        </EuiFlexItem>
      </EuiFlexGroup>

      {detailsIsOpen && (
        <div>
          <EuiText size="xs">
            <span>
              <FormattedMessage
                id="core.healthcheck.check.details.date"
                defaultMessage="{startedAt} - {finishedAt} ({duration}s)"
                values={{
                  startedAt: startedAt ? formatDate(startedAt) : '-',
                  finishedAt: finishedAt ? formatDate(finishedAt) : '-',
                  duration: duration || '-',
                }}
              />
            </span>
          </EuiText>
          {error && (
            <EuiText size="xs" color="danger">
              {error}
            </EuiText>
          )}
        </div>
      )}
    </>
  );
};
