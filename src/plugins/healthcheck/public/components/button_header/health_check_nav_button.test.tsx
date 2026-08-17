/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { render } from '@testing-library/react';
import { BehaviorSubject } from 'rxjs';
import { HealthCheckStatus } from 'src/core/common/healthcheck';
import { HealthCheckNavButton, HealthCheckNavButtonProps } from './health_check_nav_button';
import { setCore } from '../../dashboards_services';

jest.mock('@elastic/eui', () => {
  const actual = jest.requireActual('@elastic/eui');
  return {
    ...actual,
    EuiIcon: ({ type, color }: { type: string; color?: string }) => (
      <span data-test-subj="healthcheck-icon" data-icon-type={type} data-icon-color={color} />
    ),
  };
});

const coreStart = {
  uiSettings: { get: jest.fn().mockReturnValue(false) },
  application: {
    getUrlForApp: jest.fn().mockReturnValue('/app/healthcheck'),
    navigateToUrl: jest.fn(),
  },
} as any;

const buildStatus = (status: HealthCheckStatus['status']): HealthCheckStatus => ({
  status,
  checks: [],
});

const renderButton = (status: HealthCheckStatus['status']) => {
  const props: HealthCheckNavButtonProps = {
    coreStart,
    status$: new BehaviorSubject<HealthCheckStatus>(buildStatus(status)),
    fetch: jest.fn().mockResolvedValue(undefined),
    getConfig: jest.fn().mockResolvedValue({ interval: 0 }),
  };
  return render(<HealthCheckNavButton {...props} />);
};

describe('HealthCheckNavButton', () => {
  beforeEach(() => {
    setCore(coreStart);
    jest.clearAllMocks();
  });

  it('does not render when the overall status is green', () => {
    const { queryByTestId } = renderButton('green');
    expect(queryByTestId('healthcheck-icon')).toBeNull();
  });

  it('does not render when the overall status is gray', () => {
    const { queryByTestId } = renderButton('gray');
    expect(queryByTestId('healthcheck-icon')).toBeNull();
  });

  it('renders a pulse icon when the overall status is yellow', () => {
    const { getByTestId } = renderButton('yellow');
    const icon = getByTestId('healthcheck-icon');
    expect(icon).toHaveAttribute('data-icon-type', 'pulse');
    expect(icon).toHaveAttribute('data-icon-color', 'warning');
  });

  it('renders a pulse icon when the overall status is red', () => {
    const { getByTestId } = renderButton('red');
    const icon = getByTestId('healthcheck-icon');
    expect(icon).toHaveAttribute('data-icon-type', 'pulse');
    expect(icon).toHaveAttribute('data-icon-color', 'danger');
  });
});
