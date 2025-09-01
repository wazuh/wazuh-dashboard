/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useEffect, useRef, useState } from 'react';
import { FormattedMessage, I18nProvider } from '@osd/i18n/react';
import {
  EuiButtonEmpty,
  EuiContextMenuPanel,
  EuiHeaderSectionItemButton,
  EuiHealth,
  EuiButtonIcon,
  EuiPopover,
  EuiToolTip,
  EuiText,
} from '@elastic/eui';
import useObservable from 'react-use/lib/useObservable';
import { BehaviorSubject, interval, Subscription } from 'rxjs';
import { HealthCheckConfig } from 'src/core/common/healthcheck';
import { getHealthFromStatus } from './services/health';
import { HealthCheckServiceStart, HealthCheckServiceStartDeps } from '../types';
import { HealthCheckStatus } from '../service';

export interface HealthCheckNavButtonProps {
  coreStart: HealthCheckServiceStartDeps;
  status$: BehaviorSubject<HealthCheckStatus>;
  fetch: HealthCheckServiceStart['client']['internal']['fetch'];
  run: HealthCheckServiceStart['client']['internal']['run'];
  getConfig: () => Promise<HealthCheckConfig>;
  formatDate: (date: string) => string;
}
export const HealthCheckNavButton = (props: HealthCheckNavButtonProps) => {
  const [isPopoverOpen, setPopoverOpen] = useState<boolean>(false);
  const { status } = useObservable(props.status$, props.status$.getValue());
  const updateInterval = useRef<Subscription>();

  useEffect(() => {
    props.getConfig().then((config) => {
      props.fetch().catch();
      const intervalConfig = config?.interval;
      if (interval) {
        updateInterval.current = interval(intervalConfig).subscribe(() => props.fetch());
      }
    });

    return () => updateInterval?.current?.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isPlacedInLeftNav = props.coreStart.uiSettings.get('home:useNewHomePage');

  const overallStatusIndicator = (
    <EuiHealth
      color={getHealthFromStatus(status)}
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
            status,
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

  const contextMenuPanel = (
    <div style={{ maxWidth: '400px' }}>
      <EuiText>
        <FormattedMessage
          id="core.healthcheck.status.contextMenu"
          defaultMessage="Health check status: {status} "
          values={{
            status,
          }}
        />
        <EuiToolTip position="bottom" content="View more details">
          <EuiButtonIcon
            href="/app/healthcheck"
            iconType="iInCircle"
            aria-label="Health check status"
          />
        </EuiToolTip>
      </EuiText>
    </div>
  );

  const popover = (
    <EuiPopover
      data-test-subj="healthcheck-popover"
      id="healthcheckMenu"
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
  );

  return (
    <I18nProvider>
      {isPlacedInLeftNav ? (
        popover
      ) : (
        <EuiHeaderSectionItemButton size="l">{popover}</EuiHeaderSectionItemButton>
      )}
    </I18nProvider>
  );
};
