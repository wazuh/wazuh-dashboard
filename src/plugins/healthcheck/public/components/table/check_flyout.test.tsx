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

const description = {
  title: 'Server API run as',
  description: 'Checks that the API user can use run_as.',
  remediation: 'Set run_as: true for the host.',
};

const renderFlyout = (
  flyoutDescription?: React.ComponentProps<typeof CheckFlyout>['description'],
  overrides: Partial<TaskInfo> = {}
) =>
  render(
    <I18nProvider>
      <CheckFlyout
        check={{ ...check, ...overrides }}
        description={flyoutDescription}
        formatDate={(date) => date}
        setIsFlyoutVisible={jest.fn()}
      />
    </I18nProvider>
  );

describe('CheckFlyout', () => {
  it('shows the title, name and description of a described check', () => {
    const { getByText, queryByText } = renderFlyout(description);

    expect(getByText('Server API run as')).toBeInTheDocument();
    expect(getByText('server-api:run-as')).toBeInTheDocument();
    expect(getByText('Checks that the API user can use run_as.')).toBeInTheDocument();
    expect(queryByText(/Check details for/)).toBeNull();
  });

  it('hides what to check while the check passes', () => {
    const { queryByText } = renderFlyout(description);

    expect(queryByText('What to check:')).toBeNull();
    expect(queryByText('Set run_as: true for the host.')).toBeNull();
  });

  it.each(['yellow', 'red'] as const)('shows what to check when the result is %s', (result) => {
    const { getByText } = renderFlyout(description, { result, error: 'run_as is disabled' });

    expect(getByText('What to check:')).toBeInTheDocument();
    expect(getByText('Set run_as: true for the host.')).toBeInTheDocument();
  });

  it('falls back to the check name when no description is registered', () => {
    const { getByText, queryByText } = renderFlyout();

    expect(getByText('Check details for server-api:run-as')).toBeInTheDocument();
    expect(queryByText('What to check:')).toBeNull();
  });
});
