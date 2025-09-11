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
  EuiPopover,
  EuiToolTip,
  EuiText,
  EuiLink,
  EuiBadge,
} from '@elastic/eui';
import useObservable from 'react-use/lib/useObservable';
import { BehaviorSubject, interval, Subscription } from 'rxjs';
import { HealthCheckConfig, HealthCheckStatus } from 'src/core/common/healthcheck';
import { HealthCheckServiceStart } from 'opensearch-dashboards/public/healthcheck';
import { CoreStart } from 'opensearch-dashboards/public';
import { getHealthFromStatus } from '../services/health';
import { RedirectAppLinks } from '../../../../opensearch_dashboards_react/public';
import { getCore } from '../../dashboards_services';
import { PLUGIN_NAME } from '../../../common';
import { BadgeResults } from '../utils/badge_results';

export interface HealthCheckNavButtonProps {
  coreStart: CoreStart;
  status$: BehaviorSubject<HealthCheckStatus>;
  fetch: HealthCheckServiceStart['client']['internal']['fetch'];
  getConfig: () => Promise<HealthCheckConfig>;
}
export const HealthCheckNavButton = ({
  getConfig,
  fetch,
  coreStart,
  status$,
}: HealthCheckNavButtonProps) => {
  const [isPopoverOpen, setPopoverOpen] = useState<boolean>(false);
  const { status, checks } = useObservable(status$, status$.getValue());
  const updateInterval = useRef<Subscription>();
  const core = getCore();

  useEffect(() => {
    getConfig().then((config) => {
      fetch().catch();
      const intervalConfig = config?.interval;
      if (interval) {
        updateInterval.current = interval(intervalConfig).subscribe(() => fetch());
      }
    });

    return () => updateInterval?.current?.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isPlacedInLeftNav = coreStart.uiSettings.get('home:useNewHomePage');

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
          id="healthcheck.status.tooltip"
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
    <EuiContextMenuPanel>
      <EuiText textAlign="center">
        <h3>
          <FormattedMessage
            id="healthcheck.status.contextMenu"
            defaultMessage="Health check status: "
          />
          <BadgeResults result={status} isEnabled={checks.some((check) => check._meta.isEnabled)} />
        </h3>

        <span>
          <FormattedMessage
            id="healthcheck.status.goToHealthCheckApp"
            defaultMessage="For more details, go to the {link}"
            values={{
              link: (
                <RedirectAppLinks application={core.application}>
                  <EuiLink href="healthcheck">{PLUGIN_NAME}</EuiLink>
                </RedirectAppLinks>
              ),
            }}
          />
        </span>
      </EuiText>
    </EuiContextMenuPanel>
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
      panelPaddingSize="m"
    >
      {contextMenuPanel}
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
