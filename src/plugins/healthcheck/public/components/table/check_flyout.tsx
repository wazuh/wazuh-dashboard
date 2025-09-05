/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */
import React from 'react';
import {
  EuiText,
  EuiCallOut,
  EuiFlexItem,
  EuiFlexGroup,
  EuiSpacer,
  EuiFlyout,
  EuiFlyoutHeader,
  EuiTitle,
  EuiFlyoutBody,
  EuiFlyoutFooter,
  EuiButton,
} from '@elastic/eui';
import { FormattedMessage } from 'react-intl';
import { TaskInfo } from '../../../../../core/common/healthcheck';

interface CheckFlyoutProps {
  check: TaskInfo;
  formatDate: (date: string) => string;
  setIsFlyoutVisible: React.Dispatch<React.SetStateAction<boolean>>;
}

export const CheckFlyout = ({ check, formatDate, setIsFlyoutVisible }: CheckFlyoutProps) => {
  const { name, duration, startedAt, finishedAt, error, _meta } = check;

  const callOut = !_meta.isEnabled && (
    <EuiCallOut iconType="help">
      <EuiText>
        <FormattedMessage
          id="healthcheck.status.disabledExplain"
          defaultMessage="Disabled. This does not run on initial or scheduled executions."
        />
      </EuiText>
    </EuiCallOut>
  );

  return (
    <EuiFlyout
      type="push"
      size="s"
      side="right"
      onClose={() => setIsFlyoutVisible(false)}
      aria-labelledby="pushedFlyoutTitle"
    >
      <EuiFlyoutHeader hasBorder>
        <EuiTitle size="m">
          <FormattedMessage
            id="healthcheck.check.details.title"
            defaultMessage="Check details for {name}"
            values={{ name }}
          />
        </EuiTitle>
      </EuiFlyoutHeader>
      <EuiFlyoutBody banner={callOut}>
        <EuiFlexGroup direction="column">
          {error && (
            <EuiFlexItem>
              <EuiText size="m">
                <p>{error}</p>
              </EuiText>
            </EuiFlexItem>
          )}
          <EuiSpacer size="xs" />
          <EuiFlexItem>
            <EuiFlexGroup>
              <EuiFlexItem>
                <EuiText size="m" color="default">
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
                <EuiText size="m" color="default">
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
                <EuiText size="m" color="default">
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
          </EuiFlexItem>
        </EuiFlexGroup>
      </EuiFlyoutBody>
      <EuiFlyoutFooter>
        <EuiButton onClick={() => setIsFlyoutVisible(false)}>Close</EuiButton>
      </EuiFlyoutFooter>
    </EuiFlyout>
  );
};
