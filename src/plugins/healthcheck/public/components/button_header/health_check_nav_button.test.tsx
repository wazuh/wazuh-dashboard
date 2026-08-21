/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { fireEvent, render, waitFor } from '@testing-library/react';
import { BehaviorSubject } from 'rxjs';
import { HealthCheckStatus, TaskInfo } from 'src/core/common/healthcheck';
import { HealthCheckNavButton, HealthCheckNavButtonProps } from './health_check_nav_button';
import { setCore } from '../../dashboards_services';
import { PLUGIN_NAME } from '../../../common';

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
    // Needed by RedirectAppLinks, which is only mounted once the popover opens.
    currentAppId$: new BehaviorSubject('healthcheck'),
  },
} as any;

const buildCheck = (name: string, result: TaskInfo['result']): TaskInfo => ({
  name,
  status: 'finished',
  result,
  createdAt: null,
  startedAt: null,
  finishedAt: null,
  duration: null,
  data: null,
  error: `${name} failed`,
  enabled: true,
  critical: false,
});

const buildStatus = (
  status: HealthCheckStatus['status'],
  checks: TaskInfo[] = []
): HealthCheckStatus => ({
  status,
  checks,
});

const renderButton = (status: HealthCheckStatus['status'], checks: TaskInfo[] = []) => {
  const props: HealthCheckNavButtonProps = {
    coreStart,
    status$: new BehaviorSubject<HealthCheckStatus>(buildStatus(status, checks)),
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

  describe('popover', () => {
    const checks = [buildCheck('server-api:run-as', 'yellow')];

    // `aria-expanded` mirrors the open state synchronously. The panel itself stays
    // mounted while OuiPopover plays its closing transition, so its presence in the
    // DOM is not a reliable signal that the popover is still open.
    it('opens the popover when the button is clicked', async () => {
      const { getByTestId, queryByRole } = renderButton('yellow', checks);
      const trigger = getByTestId('healthcheckNavButton');
      expect(trigger).toHaveAttribute('aria-expanded', 'false');
      expect(queryByRole('dialog')).toBeNull();

      fireEvent.click(trigger);

      expect(trigger).toHaveAttribute('aria-expanded', 'true');
      expect(await waitFor(() => queryByRole('dialog'))).toBeInTheDocument();
    });

    it('closes the popover when the button is clicked again', async () => {
      const { getByTestId, queryByRole } = renderButton('yellow', checks);
      const trigger = getByTestId('healthcheckNavButton');

      fireEvent.click(trigger);
      expect(trigger).toHaveAttribute('aria-expanded', 'true');

      fireEvent.click(trigger);

      expect(trigger).toHaveAttribute('aria-expanded', 'false');
      await waitFor(() => expect(queryByRole('dialog')).toBeNull());
    });

    // The panel is rendered in a portal, but React events bubble along the React tree,
    // so a toggle handler on an ancestor of OuiPopover also receives clicks coming from
    // the panel and closes it. The trigger must own the toggle instead. See #1504.
    it('keeps the popover open when clicking inside the panel', () => {
      const { getByRole, getByTestId, getByText } = renderButton('yellow', checks);
      const trigger = getByTestId('healthcheckNavButton');

      fireEvent.click(trigger);
      expect(trigger).toHaveAttribute('aria-expanded', 'true');

      fireEvent.click(getByText('run-as'));
      expect(trigger).toHaveAttribute('aria-expanded', 'true');

      fireEvent.click(getByRole('dialog'));
      expect(trigger).toHaveAttribute('aria-expanded', 'true');

      fireEvent.click(getByText('For more details, go to the', { exact: false }));
      expect(trigger).toHaveAttribute('aria-expanded', 'true');
    });

    it('closes the popover when the Health Check link is clicked', async () => {
      const { getByRole, getByTestId, queryByRole } = renderButton('yellow', checks);
      const trigger = getByTestId('healthcheckNavButton');

      fireEvent.click(trigger);
      expect(trigger).toHaveAttribute('aria-expanded', 'true');

      fireEvent.click(getByRole('link', { name: PLUGIN_NAME }));

      expect(trigger).toHaveAttribute('aria-expanded', 'false');
      await waitFor(() => expect(queryByRole('dialog')).toBeNull());
    });

    // A modified click opens the link in a new tab, so the current page — and the
    // popover on it — should stay as it is.
    it('keeps the popover open when the link is opened in a new tab', () => {
      const { getByRole, getByTestId } = renderButton('yellow', checks);
      const trigger = getByTestId('healthcheckNavButton');

      fireEvent.click(trigger);
      expect(trigger).toHaveAttribute('aria-expanded', 'true');

      fireEvent.click(getByRole('link', { name: PLUGIN_NAME }), { ctrlKey: true });

      expect(trigger).toHaveAttribute('aria-expanded', 'true');
    });
  });

  describe('popover when placed in the left nav', () => {
    const checks = [buildCheck('server-api:run-as', 'yellow')];

    beforeEach(() => {
      coreStart.uiSettings.get.mockReturnValue(true);
    });

    afterEach(() => {
      coreStart.uiSettings.get.mockReturnValue(false);
    });

    it('toggles the popover from the button and ignores clicks inside the panel', () => {
      const { getByRole, getByTestId, getByText } = renderButton('yellow', checks);
      const trigger = getByTestId('healthcheckNavButton');
      expect(trigger).toHaveAttribute('aria-expanded', 'false');

      fireEvent.click(trigger);
      expect(trigger).toHaveAttribute('aria-expanded', 'true');

      fireEvent.click(getByText('run-as'));
      expect(trigger).toHaveAttribute('aria-expanded', 'true');

      fireEvent.click(getByRole('dialog'));
      expect(trigger).toHaveAttribute('aria-expanded', 'true');

      fireEvent.click(trigger);
      expect(trigger).toHaveAttribute('aria-expanded', 'false');
    });
  });
});
