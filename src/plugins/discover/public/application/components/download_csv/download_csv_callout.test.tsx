/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { IntlProvider } from 'react-intl';
import { render, screen } from '@testing-library/react';
import { DiscoverDownloadCsvCallout } from './download_csv_callout';
import { MAX_DOWNLOAD_CSV_COUNT, REPORTS_CSV_MAX_ROWS_SETTING } from './constants';
import { setServices } from '../../../opensearch_dashboards_services';
import { discoverPluginMock } from '../../../mocks';

const TestHarness = () => {
  return (
    <IntlProvider locale="en">
      <DiscoverDownloadCsvCallout />
    </IntlProvider>
  );
};

describe('DiscoverDownloadCsvCallout', () => {
  beforeEach(() => {
    setServices(discoverPluginMock.createDiscoverServicesMock());
  });

  it('renders text correctly', () => {
    render(<TestHarness />);
    expect(
      screen.getByText(
        `There is a limit of ${MAX_DOWNLOAD_CSV_COUNT.toLocaleString()} total result downloads.`,
        { exact: false }
      )
    ).toBeInTheDocument();

    expect(
      screen.getByText('This value can be changed using the', { exact: false })
    ).toBeInTheDocument();
    expect(screen.getByText(REPORTS_CSV_MAX_ROWS_SETTING)).toBeInTheDocument();
    expect(screen.getByText('Dashboard Management > Advanced settings')).toBeInTheDocument();
  });

  it('links to the Advanced settings page filtered to the setting', () => {
    render(<TestHarness />);
    const link = screen.getByText('Dashboard Management > Advanced settings').closest('a');
    expect(link).toHaveAttribute(
      'href',
      expect.stringContaining(
        `/app/management/opensearch-dashboards/settings/${REPORTS_CSV_MAX_ROWS_SETTING}`
      )
    );
  });
});
