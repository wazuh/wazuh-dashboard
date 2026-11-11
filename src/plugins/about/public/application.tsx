/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { i18n } from '@osd/i18n';
import { I18nProvider } from '@osd/i18n/react';
import { EuiPage, EuiPageBody, EuiSpacer, EuiProgress } from '@elastic/eui';
import { CoreStart } from 'opensearch-dashboards/public';
import { AboutAppInfo } from './components/app_info';
import { AboutGeneralInfo } from './components/general_info';
import { formatBuild } from './format_build';
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
  // Wazuh: the build is composed from the version, the stage and the revision number.
  const buildInfo = core.injectedMetadata.getWazuhBuildInfo();
  const build = formatBuild({
    version: buildInfo.version,
    stage: buildInfo.stage,
    revision: buildInfo.revision,
    versionOverride: branding.applicationVersion,
    revisionOverride: branding.applicationRevision,
  });
  const communityLinks = config.communityLinks;
  const pluginAppName = branding.applicationTitle || 'Wazuh dashboard';
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
            <AboutAppInfo build={build} clusterUuid={clusterUuid} />
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
  const title = i18n.translate('about.breadcrumbs.title', { defaultMessage: 'About' });
  core.chrome.setBreadcrumbs([{ text: title }]);
  core.chrome.docTitle.change(title);

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
