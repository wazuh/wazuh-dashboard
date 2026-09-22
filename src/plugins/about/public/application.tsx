/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { I18nProvider } from '@osd/i18n/react';
import { EuiPage, EuiPageBody, EuiSpacer, EuiProgress } from '@elastic/eui';
import { CoreStart } from 'opensearch-dashboards/public';
import { AboutAppInfo } from './components/app_info';
import { AboutGeneralInfo } from './components/general_info';
import { ABOUT_API_ROUTE } from '../common/constants';
import type { AboutConfigType } from '../common/config';

interface AboutAppProps {
  core: CoreStart;
  config: AboutConfigType;
}

const AboutApp = ({ core, config }: AboutAppProps) => {
  const [clusterUuid, setClusterUuid] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    core.http
      .get<{ clusterUuid: string | null }>(ABOUT_API_ROUTE)
      .then(({ clusterUuid: uuid }) => setClusterUuid(uuid))
      .catch(() => setClusterUuid(null))
      .finally(() => setLoading(false));
  }, [core.http]);

  const branding = core.injectedMetadata.getBranding();
  // Wazuh: same value shown in the help menu badge, and the same fallback.
  const version = branding.applicationVersion || core.injectedMetadata.getWazuhBuildInfo().version;
  const communityLinks = config.communityLinks;
  const pluginAppName = branding.applicationTitle || 'Wazuh';
  const darkMode = core.uiSettings.get('theme:darkMode');

  return (
    <EuiPage paddingSize="m">
      <EuiPageBody>
        {loading ? (
          <>
            <EuiProgress size="xs" color="primary" />
            <EuiSpacer size="l" />
          </>
        ) : (
          <>
            <AboutAppInfo version={version} clusterUuid={clusterUuid} />
            <EuiSpacer size="l" />
          </>
        )}
        <AboutGeneralInfo
          pluginAppName={pluginAppName}
          communityLinks={communityLinks}
          darkMode={darkMode}
        />
      </EuiPageBody>
    </EuiPage>
  );
};

export function renderApp(core: CoreStart, config: AboutConfigType, element: HTMLElement) {
  const root = createRoot(element);
  root.render(
    <I18nProvider>
      <AboutApp core={core} config={config} />
    </I18nProvider>
  );

  return () => {
    core.chrome.docTitle.reset();
    root.unmount();
  };
}
