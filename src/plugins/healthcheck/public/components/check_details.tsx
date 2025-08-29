/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */
import React, { useState } from 'react';
import { EuiCallOut, EuiText, EuiToolTip, EuiBadge } from '@elastic/eui';
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
    <EuiText color={_meta?.isEnabled ? 'default' : 'subdued'} size="s">
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
      <EuiCallOut
        color={colorCallOut[check.result].color}
        title={nameCheck}
        iconType={colorCallOut[check.result].iconType}
      >
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
      </EuiCallOut>
    </>
  );
};
