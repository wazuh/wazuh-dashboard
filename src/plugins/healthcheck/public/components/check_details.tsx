/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */
import React, { useState } from 'react';
import {
  EuiText,
  EuiToolTip,
  EuiBadge,
  EuiFlexItem,
  EuiFlexGroup,
  EuiSpacer,
  EuiFlyout,
  EuiFlyoutHeader,
  EuiTitle,
  EuiFlyoutBody,
  EuiFlyoutFooter,
  EuiButton,
  EuiButtonEmpty,
  EuiHorizontalRule,
  EuiLink,
} from '@elastic/eui';
import { FormattedMessage } from 'react-intl';
import { TaskInfo } from 'src/core/common/healthcheck';

interface CheckDetailsProps {
  check: TaskInfo;
  formatDate: (date: string) => string;
}

import wazuh from '../../../../../package.json';

export const WAZUH_MAJOR = wazuh.wazuh.version.split('.')[0];
export const WAZUH_MINOR = wazuh.wazuh.version.split('.')[1];

export const CheckDetails = ({ check, formatDate }: CheckDetailsProps) => {
  const [isFlyoutVisible, setIsFlyoutVisible] = useState(false);

  const { name, duration, startedAt, finishedAt, error, _meta } = check;

  const colorCallOut = {
    green: { color: 'success', iconType: 'check' },
    yellow: { color: 'warning', iconType: 'alert' },
    red: { color: 'danger', iconType: 'cross' },
    gray: { color: 'primary', iconType: 'question' },
  };

  let nameCheck = (
    <EuiButtonEmpty
      size="s"
      contentProps={{ style: { justifyContent: 'flex-start' } }}
      onClick={() => setIsFlyoutVisible(!isFlyoutVisible)}
    >
      <EuiText color={_meta?.isEnabled ? 'default' : 'subdued'} size="m">
        Check [ <span style={{ color: check.result }}>{name}</span> ]{' '}
        <EuiBadge color={colorCallOut[check.result].color}>
          {_meta?.isCritical ? 'Critical' : 'Minor'}
        </EuiBadge>
      </EuiText>
    </EuiButtonEmpty>
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

  const flyout = (
    <EuiFlyout
      type="overlay"
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
      <EuiFlyoutBody>
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
          <EuiHorizontalRule />
          <EuiFlexItem>
            <EuiText size="m" color="default">
              <FormattedMessage
                id="healthcheck.check.details.troubleshooting"
                defaultMessage="For troubleshooting, you can check the following documentation: "
              />
              <EuiLink
                href={`https://documentation.wazuh.com/${WAZUH_MAJOR}.${WAZUH_MINOR}/user-manual/wazuh-dashboard/troubleshooting.html`}
                external
              >
                wazuh-dashboard - troubleshooting
              </EuiLink>
            </EuiText>
          </EuiFlexItem>
        </EuiFlexGroup>
      </EuiFlyoutBody>
      <EuiFlyoutFooter>
        <EuiButton onClick={() => setIsFlyoutVisible(false)}>Close</EuiButton>
      </EuiFlyoutFooter>
    </EuiFlyout>
  );

  return (
    <>
      {nameCheck}
      {isFlyoutVisible && flyout}
    </>
  );
};
