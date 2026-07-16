/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import './download_csv_callout.scss';
import React from 'react';
import { EuiCallOut, EuiLink, EuiText } from '@elastic/eui';
import { FormattedMessage } from '@osd/i18n/react';
import { MAX_DOWNLOAD_CSV_COUNT, REPORTS_CSV_MAX_ROWS_SETTING } from './constants';
import { getServices } from '../../../opensearch_dashboards_services';

export interface DiscoverDownloadCsvCalloutProps {
  max?: number;
}

export const DiscoverDownloadCsvCallout = ({
  max = MAX_DOWNLOAD_CSV_COUNT,
}: DiscoverDownloadCsvCalloutProps) => {
  const { addBasePath } = getServices();

  return (
    <EuiCallOut
      className="dscDownloadCsvCallout"
      data-test-subj="dscDownloadCsvCallout"
      color="warning"
    >
      <EuiText size="s" className="dscDownloadCsvCallout__text">
        <FormattedMessage
          id="discover.downloadCsvCallout"
          defaultMessage="There is a limit of {max} total result downloads.{lineBreak}This value can be changed using the {settingName} setting in {advancedSettingsLink}."
          values={{
            max: max.toLocaleString(),
            lineBreak: <br />,
            settingName: <strong>{REPORTS_CSV_MAX_ROWS_SETTING}</strong>,
            advancedSettingsLink: (
              <EuiLink
                target="_blank"
                data-test-subj="dscDownloadCsvCalloutAdvancedSettingsLink"
                href={addBasePath(
                  `/app/management/opensearch-dashboards/settings/${REPORTS_CSV_MAX_ROWS_SETTING}`
                )}
              >
                <FormattedMessage
                  id="discover.downloadCsvCallout.advancedSettingsLinkText"
                  defaultMessage="Dashboard Management > Advanced settings"
                />
              </EuiLink>
            ),
          }}
        />
      </EuiText>
    </EuiCallOut>
  );
};
