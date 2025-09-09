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
import { getHealthFromStatus } from '../services/health';

interface CheckFlyoutProps {
  check: TaskInfo;
  formatDate: (date: string) => string;
  setIsFlyoutVisible: React.Dispatch<React.SetStateAction<boolean>>;
}

export const CheckFlyout = ({ check, formatDate, setIsFlyoutVisible }: CheckFlyoutProps) => {
  const { name, duration, startedAt, finishedAt, error, _meta, result, status } = check;

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
                <FormattedMessage id="healthcheck.check.details.error" defaultMessage="Error:" />
              </EuiText>
              <EuiSpacer size="s" />
              <EuiCallOut size="s" color={getHealthFromStatus(result)}>
                <p>{error}</p>
              </EuiCallOut>
            </EuiFlexItem>
          )}
          <EuiSpacer />
          <EuiFlexItem>
            <EuiFlexGroup>
              <EuiFlexItem>
                <EuiText size="m" color="default">
                  <FormattedMessage
                    id="healthcheck.check.details._meta.isEnabled"
                    defaultMessage="Enabled: {isEnabled}"
                    values={{ isEnabled: _meta.isEnabled ? 'Yes' : 'No' }}
                  />
                </EuiText>
              </EuiFlexItem>
              <EuiFlexItem>
                <EuiText size="m" color="default">
                  <FormattedMessage
                    id="healthcheck.check.details._meta.isCritical"
                    defaultMessage="Critical: {isCritical}"
                    values={{ isCritical: _meta.isCritical ? 'Yes' : 'No' }}
                  />
                </EuiText>
              </EuiFlexItem>
              <EuiFlexItem>
                <EuiText size="m" color="default">
                  <FormattedMessage
                    id="healthcheck.check.details.status"
                    defaultMessage="Status: {status}"
                    values={{ status }}
                  />
                </EuiText>
              </EuiFlexItem>
            </EuiFlexGroup>
            <EuiSpacer />
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
