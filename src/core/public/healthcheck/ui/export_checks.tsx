/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { EuiButtonIcon, EuiToolTip } from '@elastic/eui';
import { FormattedMessage } from '@osd/i18n/react';
import { useAsyncAction } from './hook/use_async_action';

/**
 * Trigger a download of a file with given content.
 *
 * @param {string} filename      - The name for the downloaded file (e.g. "report.txt").
 * @param {string|Blob|Uint8Array} content  - File contents as text, Blob, or byte array.
 * @param {string} [mimeType]    - MIME type of the file (defaults to "text/plain").
 */
function downloadFile(filename, content, mimeType = 'text/plain') {
  // Normalize content into a Blob
  let blob;
  if (content instanceof Blob) {
    blob = content;
  } else if (content instanceof Uint8Array) {
    blob = new Blob([content], { type: mimeType });
  } else {
    blob = new Blob([String(content)], { type: mimeType });
  }

  // Create an object URL and anchor element
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;

  // Append, click, and clean up
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

export const ButtonExportHealthCheck = (data) => {
  const action = useAsyncAction(() =>
    downloadFile('healthcheck.json', JSON.stringify(data, null, 2), 'application/json')
  );
  return (
    <EuiToolTip
      content={
        <FormattedMessage
          id="core.healthcheck.export_healthcheck"
          defaultMessage="Export health check data"
        />
      }
      position="bottom"
    >
      <EuiButtonIcon
        iconType="exportAction"
        onClick={action.run}
        isDisabled={action.running}
        iconSize="l"
        aria-label="Export health check data"
      />
    </EuiToolTip>
  );
};
