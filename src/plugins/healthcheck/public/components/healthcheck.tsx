/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useEffect } from 'react';
import { i18n } from '@osd/i18n';
import { FormattedMessage, I18nProvider } from '@osd/i18n/react';
import {
  EuiFlexGroup,
  EuiFlexItem,
  EuiHorizontalRule,
  EuiButtonEmpty,
  EuiLink,
} from '@elastic/eui';
import useObservable from 'react-use/lib/useObservable';
import { useMount } from 'react-use';
import { ButtonExportHealthCheck } from './export_checks';
import { getHealthCheck } from '../dashboards_services';
import { getCore } from '../dashboards_services';
import { ChecksTable } from './table/checks_table';
import { TitleView } from './title_view';
import { WAZUH_MAJOR, WAZUH_MINOR } from '../constants';

export const HealthCheck = () => {
  const core = getCore();

  useMount(() => {
    core.chrome.setBreadcrumbs([
      {
        text: i18n.translate('healthcheck.breadcrumbs.title', {
          defaultMessage: 'Health check',
        }),
      },
    ]);

    core.chrome.docTitle.change(
      i18n.translate('healthcheck.pageTitle', { defaultMessage: 'Health check' })
    );
  });

  const { status$, client, getConfig } = getHealthCheck();
  const {
    internal: { fetch },
  } = client;
  const { status, checks } = useObservable(status$, status$.getValue());

  useEffect(() => {
    getConfig().then(() => {
      fetch().catch();
    });
  }, [fetch, getConfig]);

  const contextMenuPanel = (
    <div>
      <EuiFlexGroup
        gutterSize="xs"
        justifyContent="spaceBetween"
        alignItems="center"
        responsive={false}
      >
        <EuiFlexItem grow={false}>
          <TitleView status={status} checks={checks} />
        </EuiFlexItem>
        <EuiFlexItem grow={false}>
          <EuiFlexGroup gutterSize="xs" responsive={false} alignItems="center">
            <EuiFlexItem grow={false}>
              <ButtonExportHealthCheck data={{ status, checks }} />
            </EuiFlexItem>
            <EuiFlexItem grow={false}>
              <EuiButtonEmpty iconType="iInCircle">
                <EuiLink
                  href={`https://documentation.wazuh.com/${WAZUH_MAJOR}.${WAZUH_MINOR}/user-manual/wazuh-dashboard/troubleshooting.html`}
                  external
                  target="_blank"
                >
                  <FormattedMessage
                    id="healthcheck.check.details.troubleshooting.linkTroubleshooting"
                    defaultMessage="Documentation"
                  />
                </EuiLink>
              </EuiButtonEmpty>
            </EuiFlexItem>
          </EuiFlexGroup>
        </EuiFlexItem>
      </EuiFlexGroup>
      <EuiHorizontalRule margin="xs" />
      <ChecksTable checks={checks} />
    </div>
  );

  return <I18nProvider>{contextMenuPanel}</I18nProvider>;
};
