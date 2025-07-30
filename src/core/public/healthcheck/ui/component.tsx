/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useEffect, useState } from 'react';
import { FormattedMessage, I18nProvider } from '@osd/i18n/react';
import {
  EuiButtonEmpty,
  EuiContextMenuPanel,
  EuiHeaderSectionItemButton,
  EuiHealth,
  EuiFlexGroup,
  EuiPopover,
  EuiToolTip,
  EuiFlexItem,
  EuiText,
  EuiButtonIcon,
} from '@elastic/eui';
import useObservable from 'react-use/lib/useObservable';

function computeOverallChecks(checks) {
  let status = 'green';

  if (checks.some(({ result, _meta }) => !_meta.isCritical && result === 'fail')) {
    status = 'yellow';
  }

  if (checks.some(({ result, _meta }) => _meta.isCritical && result === 'fail')) {
    status = 'red';
  }

  return status;
}

function computeCheckStatus(check) {
  return check.result === 'success' ? 'green' : 'red';
}

const mapStatusHealth = {
  green: 'success',
  yellow: 'warning',
  red: 'danger',
  default: 'gray',
};

const CheckDetails = ({ check }) => {
  // TODO: format dates
  const { name, duration, startedAt, finishedAt } = check;
  const [detailsIsOpen, setDetailsIsOpen] = useState<boolean>(false);
  const status = computeCheckStatus(check);
  return (
    <>
      <EuiFlexGroup justifyContent="spaceBetween">
        <EuiFlexItem grow={false}>
          <EuiToolTip content={`Health check status: ${status}`} position="bottom">
            <EuiHealth color={mapStatusHealth[status] || mapStatusHealth.default}>{name}</EuiHealth>
          </EuiToolTip>
        </EuiFlexItem>
        <EuiFlexItem grow={false}>
          <EuiButtonIcon iconType="iInCircle" onClick={() => setDetailsIsOpen((state) => !state)} />
        </EuiFlexItem>
      </EuiFlexGroup>

      {detailsIsOpen && (
        <div>
          <EuiText size="xs">
            <span>
              {startedAt} - {finishedAt} ({duration}s)
            </span>
          </EuiText>
        </div>
      )}
    </>
  );
};

export const HealthCheckNavButton = (props) => {
  const [isPopoverOpen, setPopoverOpen] = React.useState<boolean>(false);
  const { ok, checks } = useObservable(props.status$, props.status$.getValue());

  const overallStatus = computeOverallChecks(checks);

  const isPlacedInLeftNav = props.coreStart.uiSettings.get('home:useNewHomePage');

  const overallStatusIndicator = (
    <EuiHealth
      color={mapStatusHealth[overallStatus] || mapStatusHealth.default}
      onClick={() => setPopoverOpen((prevState) => !prevState)}
    />
  );

  // ToDo: Add aria-label and tooltip when isPlacedInLeftNav is true
  const button = (
    <EuiToolTip
      content={
        <FormattedMessage
          id="core.healthcheck.status.tooltip"
          defaultMessage="Health check status: {status}"
          values={{
            status: overallStatus,
          }}
        />
      }
      position="bottom"
    >
      {overallStatusIndicator}
    </EuiToolTip>
  );
  const innerElement = isPlacedInLeftNav ? (
    <EuiButtonEmpty
      size="xs"
      flush="both"
      className="accountNavButton"
      aria-expanded={isPopoverOpen}
      aria-haspopup="true"
    >
      {button}
    </EuiButtonEmpty>
  ) : (
    button
  );

  useEffect(() => {
    props.fetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const contextMenuPanel = (
    <div style={{ maxWidth: '400px' }}>
      <EuiFlexGroup
        gutterSize="xs"
        justifyContent="spaceBetween"
        alignItems="center"
        responsive={false}
      >
        <EuiFlexItem grow={false}>
          <EuiToolTip
            content={
              <FormattedMessage
                id="core.healthcheck.status.tooltip"
                defaultMessage="Health check status: {status}"
                values={{
                  status: overallStatus,
                }}
              />
            }
            position="bottom"
          >
            <EuiHealth color={mapStatusHealth[overallStatus] || mapStatusHealth.default}>
              <EuiText>
                <h3>
                  <FormattedMessage id="core.healthcheck.title" defaultMessage="Health check" />
                </h3>
              </EuiText>
            </EuiHealth>
          </EuiToolTip>
        </EuiFlexItem>
        <EuiFlexItem grow={false}>
          <EuiFlexGroup gutterSize="xs">
            <EuiFlexItem grow={false}>
              <EuiToolTip
                content={<FormattedMessage id="core.healthcheck.run" defaultMessage="Run checks" />}
                position="bottom"
              >
                <EuiButtonIcon iconType="refresh" onClick={props.run} />
              </EuiToolTip>
            </EuiFlexItem>
          </EuiFlexGroup>
        </EuiFlexItem>
      </EuiFlexGroup>
      <EuiFlexGroup direction="column" gutterSize="xs" responsive={false}>
        {checks.map((check) => (
          <EuiFlexItem key={check.name}>
            <div>
              <CheckDetails check={check} />
            </div>
          </EuiFlexItem>
        ))}
      </EuiFlexGroup>
    </div>
  );

  return (
    <I18nProvider>
      <EuiHeaderSectionItemButton id="user-icon-btn" size="l">
        <EuiPopover
          data-test-subj="account-popover"
          id="actionsMenu"
          anchorPosition={isPlacedInLeftNav ? 'rightDown' : undefined}
          button={innerElement}
          isOpen={isPopoverOpen}
          closePopover={() => {
            setPopoverOpen(false);
          }}
          panelPaddingSize="s"
        >
          <EuiContextMenuPanel>{contextMenuPanel}</EuiContextMenuPanel>
        </EuiPopover>
      </EuiHeaderSectionItemButton>
    </I18nProvider>
  );
};
