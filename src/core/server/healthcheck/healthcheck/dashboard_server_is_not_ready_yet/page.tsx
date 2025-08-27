import React from 'react';
import { NotReadyServerProps } from './types';
import WazuhDashboardLogo from './components/wazuh-dashboard-logo';

export default function Page({
  documentationTroubleshootingLink,
}: Pick<NotReadyServerProps, 'documentationTroubleshootingLink'>) {
  return (
    <>
      <div className="title">
        <WazuhDashboardLogo />{' '}
        <div>
          <span className="server-is">server is</span>{' '}
          <div className="not-ready">not ready yet</div>
        </div>
      </div>
      {documentationTroubleshootingLink ? (
        <div>
          For more information, please visit the{' '}
          <a rel="noopener noreferrer" target="_blank" href={documentationTroubleshootingLink}>
            Troubleshooting
          </a>{' '}
          documentation.
        </div>
      ) : null}
    </>
  );
}
