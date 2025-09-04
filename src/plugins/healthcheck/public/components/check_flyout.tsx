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
  EuiHorizontalRule,
  EuiLink,
} from '@elastic/eui';
import { FormattedMessage } from 'react-intl';
import { TaskInfo } from 'src/core/common/healthcheck';

interface CheckFlyoutProps {
  check: TaskInfo;
  formatDate: (date: string) => string;
  setIsFlyoutVisible: React.Dispatch<React.SetStateAction<boolean>>;
}

import wazuh from '../../../../../package.json';

export const WAZUH_MAJOR = wazuh.wazuh.version.split('.')[0];
export const WAZUH_MINOR = wazuh.wazuh.version.split('.')[1];

export const CheckFlyout = ({ check, formatDate, setIsFlyoutVisible }: CheckFlyoutProps) => {
  const { name, duration, startedAt, finishedAt, error, _meta } = check;

  const callOut = (
    <EuiCallOut iconType="help">
      <EuiText>
        <FormattedMessage
          id="healthcheck.check.details.troubleshooting"
          defaultMessage="For troubleshooting, you can check the following documentation: "
        />
        <EuiLink
          href={`https://documentation.wazuh.com/${WAZUH_MAJOR}.${WAZUH_MINOR}/user-manual/wazuh-dashboard/troubleshooting.html`}
          external
        >
          <FormattedMessage
            id="healthcheck.check.details.troubleshooting.linkTroubleshooting"
            defaultMessage="wazuh-dashboard - troubleshooting"
          />
        </EuiLink>
      </EuiText>
      {!_meta.isEnabled && (
        <>
          <EuiHorizontalRule />
          <EuiText>
            <FormattedMessage
              id="healthcheck.status.disabledExplain"
              defaultMessage="Disabled. This does not run on initial or scheduled executions."
            />
          </EuiText>
        </>
      )}
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
