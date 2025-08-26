import React from 'react';
import { NotReadyServerProps } from './types';

export default function Page({ appName, documentationTroubleshootingLink }: NotReadyServerProps) {
  return (
    <>
      <p>{appName} server is not ready yet</p>
      <p>
        If this message persists after a time of the initialization, this could be caused for some
        problem. Review the app logs for more information.
      </p>
      {documentationTroubleshootingLink ? (
        <div>
          <a rel="noopener noreferrer" target="_blank" href={documentationTroubleshootingLink}>
            Troubleshooting
          </a>
        </div>
      ) : null}
    </>
  );
}
