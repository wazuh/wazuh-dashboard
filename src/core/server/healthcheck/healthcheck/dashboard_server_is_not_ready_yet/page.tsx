import React from 'react';
import { NotReadyServerProps, OmitStrict } from './types';
import WazuhDashboardLogo from "./components/wazuh-dashboard-logo";

export default function Page({
  appName,
  documentationTroubleshootingLink,
}: OmitStrict<NotReadyServerProps, 'serverBasePath'>) {
  return (
    <>
      <div className="title"><WazuhDashboardLogo /> <span className="server-is">server is</span> <div className="not-ready">not ready yet</div></div>
      {documentationTroubleshootingLink ? (
        <div>
          For more information, please visit the{' '}
          <a rel="noopener noreferrer" target="_blank" href={documentationTroubleshootingLink}>
            Troubleshooting
          </a>
          {' '}documentation.
        </div>
      ) : null}
    </>
  );
}
