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
  EuiDescriptionList,
  EuiDescriptionListTitle,
  EuiDescriptionListDescription,
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
            <EuiDescriptionList type="responsiveColumn">
              <EuiDescriptionListTitle>
                <FormattedMessage
                  id="healthcheck.check.details._meta.isEnabled"
                  defaultMessage="Enabled:"
                />
              </EuiDescriptionListTitle>

              <EuiDescriptionListDescription>
                <FormattedMessage
                  id="healthcheck.check.details._meta.isEnabledValue"
                  defaultMessage="{isEnabled}"
                  values={{ isEnabled: _meta.isEnabled ? 'Yes' : 'No' }}
                />
              </EuiDescriptionListDescription>

              <EuiDescriptionListTitle>
                <FormattedMessage
                  id="healthcheck.check.details._meta.isCritical"
                  defaultMessage="Critical:"
                />
              </EuiDescriptionListTitle>

              <EuiDescriptionListDescription>
                <FormattedMessage
                  id="healthcheck.check.details._meta.isCriticalValue"
                  defaultMessage="{isCritical}"
                  values={{ isCritical: _meta.isCritical ? 'Yes' : 'No' }}
                />
              </EuiDescriptionListDescription>

              <EuiDescriptionListTitle>
                <FormattedMessage id="healthcheck.check.details.status" defaultMessage="Status:" />
              </EuiDescriptionListTitle>
              <EuiDescriptionListDescription>
                <FormattedMessage
                  id="healthcheck.check.details.statusValue"
                  defaultMessage="{status}"
                  values={{ status }}
                />
              </EuiDescriptionListDescription>

              <EuiDescriptionListTitle>
                <FormattedMessage id="healthcheck.check.details.result" defaultMessage="Result:" />
              </EuiDescriptionListTitle>
              <EuiDescriptionListDescription>
                <FormattedMessage
                  id="healthcheck.check.details.resultValue"
                  defaultMessage="{result}"
                  values={{ result }}
                />
              </EuiDescriptionListDescription>

              <EuiDescriptionListTitle>
                <FormattedMessage
                  id="healthcheck.check.details.startedAt"
                  defaultMessage="Created:"
                />
              </EuiDescriptionListTitle>
              <EuiDescriptionListDescription>
                <FormattedMessage
                  id="healthcheck.check.details.startedAtValue"
                  defaultMessage="{startedAt}"
                  values={{ startedAt: startedAt ? formatDate(startedAt) : '-' }}
                />
              </EuiDescriptionListDescription>

              <EuiDescriptionListTitle>
                <FormattedMessage
                  id="healthcheck.check.details.finishedAt"
                  defaultMessage="Finished:"
                />
              </EuiDescriptionListTitle>
              <EuiDescriptionListDescription>
                <FormattedMessage
                  id="healthcheck.check.details.finishedAtValue"
                  defaultMessage="{finishedAt}"
                  values={{ finishedAt: finishedAt ? formatDate(finishedAt) : '-' }}
                />
              </EuiDescriptionListDescription>

              <EuiDescriptionListTitle>
                <FormattedMessage
                  id="healthcheck.check.details.duration"
                  defaultMessage="Duration:"
                />
              </EuiDescriptionListTitle>
              <EuiDescriptionListDescription>
                <FormattedMessage
                  id="healthcheck.check.details.durationValue"
                  defaultMessage="{duration}s"
                  values={{ duration: duration || '-' }}
                />
              </EuiDescriptionListDescription>
            </EuiDescriptionList>
          </EuiFlexItem>
        </EuiFlexGroup>
      </EuiFlyoutBody>
      <EuiFlyoutFooter style={{ backgroundColor: 'transparent' }}>
        <EuiButton onClick={() => setIsFlyoutVisible(false)}>Close</EuiButton>
      </EuiFlyoutFooter>
    </EuiFlyout>
  );
};
