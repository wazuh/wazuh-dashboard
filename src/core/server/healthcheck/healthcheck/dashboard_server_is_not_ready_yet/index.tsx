import React from 'react';
import { renderToString } from 'react-dom/server';
import { styles } from './styles';
import Page from './page';
import { SERVER_NOT_READY_ROUTE } from './server';

interface NotReadyServerProps {
  appName: string;
  documentationTroubleshootingLink?: string;
  serverBasePath: string;
}

const DashboardServerIsNotReadyYetComponent = ({
  appName,
  documentationTroubleshootingLink,
  serverBasePath,
}: NotReadyServerProps) => {
  return (
    <html lang="en">
      <head>
        <title>{appName}</title>
        <style dangerouslySetInnerHTML={{ __html: styles }} />
        <script src={`${serverBasePath}${SERVER_NOT_READY_ROUTE}`} defer></script>
      </head>
      <body>
        <Page
          appName={appName}
          documentationTroubleshootingLink={documentationTroubleshootingLink}
        />
        <div id="root" />
        <script
          dangerouslySetInnerHTML={{
            __html: `window.__CONFIG = ${JSON.stringify({
              appName,
              documentationTroubleshootingLink,
              serverBasePath,
            })}`,
          }}
        />
      </body>
    </html>
  );
};

export const dashboardServerIsNotReadyYet = (props: NotReadyServerProps) =>
  renderToString(DashboardServerIsNotReadyYetComponent(props));
