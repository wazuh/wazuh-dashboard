/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */
import React from 'react';
import {
  EuiCallOut,
  EuiText,
  EuiToolTip,
  EuiBadge,
  EuiFlexItem,
  EuiFlexGroup,
  EuiSpacer,
  EuiAccordion,
} from '@elastic/eui';
import { FormattedMessage } from 'react-intl';
import { TaskInfo } from 'src/core/common/healthcheck';

interface CheckDetailsProps {
  check: TaskInfo;
  formatDate: (date: string) => string;
}

export const CheckDetails = ({ check, formatDate }: CheckDetailsProps) => {
  const { name, duration, startedAt, finishedAt, error, _meta } = check;

  const colorCallOut = {
    green: { color: 'success', iconType: 'check' },
    yellow: { color: 'warning', iconType: 'alert' },
    red: { color: 'danger', iconType: 'cross' },
    gray: { color: 'primary', iconType: 'question' },
  };

  let nameCheck = (
    <EuiText color={_meta?.isEnabled ? 'default' : 'subdued'} size="xs">
      Check [ <span style={{ color: check.result }}>{name}</span> ]{' '}
      <EuiBadge color={colorCallOut[check.result].color}>
        {_meta?.isCritical ? 'Critical' : 'Minor'}
      </EuiBadge>
    </EuiText>
  );

  if (!_meta?.isEnabled) {
    nameCheck = (
      <EuiToolTip
        content={
          <FormattedMessage
            id="healthcheck.status.disabledExplain"
            defaultMessage="Disabled. This does not run on initial or scheduled executions."
          />
        }
        position="bottom"
      >
        {nameCheck}
      </EuiToolTip>
    );
  }

  const accordion = (
    <EuiAccordion id={name} buttonContent={nameCheck}>
      {error ?? (
        <>
          <EuiText size="xs" color="default">
            {error}
          </EuiText>
        </>
      )}
      <EuiSpacer size="xs" />
      <EuiFlexGroup>
        <EuiFlexItem>
          <EuiText size="xs" color="default">
            <FormattedMessage
              id="healthcheck.check.details.startedAt"
              defaultMessage="Created: {startedAt}"
              values={{
                startedAt: startedAt ? formatDate(startedAt) : '-',
              }}
            />
          </EuiText>
        </EuiFlexItem>
        <EuiFlexItem>
          <EuiText size="xs" color="default">
            <FormattedMessage
              id="healthcheck.check.details.finishedAt"
              defaultMessage="Finished: {finishedAt}"
              values={{
                finishedAt: finishedAt ? formatDate(finishedAt) : '-',
              }}
            />
          </EuiText>
        </EuiFlexItem>
        <EuiFlexItem>
          <EuiText size="xs" color="default">
            <FormattedMessage
              id="healthcheck.check.details.duration"
              defaultMessage="Duration: {duration}s"
              values={{
                duration: duration || '-',
              }}
            />
          </EuiText>
        </EuiFlexItem>
      </EuiFlexGroup>
    </EuiAccordion>
  );

  return (
    <EuiCallOut
      color={colorCallOut[check.result].color}
      title={accordion}
      iconType={colorCallOut[check.result].iconType}
    />
  );
};
