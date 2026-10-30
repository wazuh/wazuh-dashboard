/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { render } from '@testing-library/react';
import { I18nProvider } from '@osd/i18n/react';
import { TaskInfo } from '../../../../../core/common/healthcheck';
import { CheckFlyout } from './check_flyout';

const check: TaskInfo = {
  name: 'server-api:run-as',
  status: 'finished',
  result: 'green',
  createdAt: null,
  startedAt: null,
  finishedAt: null,
  duration: null,
  data: null,
  error: null,
  enabled: true,
  critical: false,
};

const renderFlyout = (description?: React.ComponentProps<typeof CheckFlyout>['description']) =>
  render(
    <I18nProvider>
      <CheckFlyout
        check={check}
        description={description}
        formatDate={(date) => date}
        setIsFlyoutVisible={jest.fn()}
      />
    </I18nProvider>
  );

describe('CheckFlyout', () => {
  it('shows the title, description and fix of a described check, and keeps its name', () => {
    const { getByText, queryByText } = renderFlyout({
      title: 'Server API run as',
      description: 'Checks that the API user can use run_as.',
      remediation: 'Set run_as: true for the host.',
    });

    expect(getByText('Server API run as')).toBeInTheDocument();
    expect(getByText('server-api:run-as')).toBeInTheDocument();
    expect(getByText('Checks that the API user can use run_as.')).toBeInTheDocument();
    expect(getByText('If it fails:')).toBeInTheDocument();
    expect(getByText('Set run_as: true for the host.')).toBeInTheDocument();
    expect(queryByText(/Check details for/)).toBeNull();
  });

  it('falls back to the check name when no description is registered', () => {
    const { getByText, queryByText } = renderFlyout();

    expect(getByText('Check details for server-api:run-as')).toBeInTheDocument();
    expect(queryByText('If it fails:')).toBeNull();
  });
});
