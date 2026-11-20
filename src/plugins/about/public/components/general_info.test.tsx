/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { render, screen } from '@testing-library/react';
import { AboutGeneralInfo } from './general_info';

describe('AboutGeneralInfo', () => {
  it('builds a complete heading and a description without the branding', () => {
    render(
      <AboutGeneralInfo pluginAppName="Wazuh dashboard" communityLinks={[]} darkMode={false} />
    );

    expect(
      screen.getByRole('heading', { name: 'Welcome to the Wazuh dashboard' })
    ).toBeInTheDocument();
    expect(screen.getByText(/^It provides management/)).toBeInTheDocument();
  });

  it('uses the branding title in the heading and description', () => {
    render(<AboutGeneralInfo pluginAppName="Acme console" communityLinks={[]} darkMode={false} />);

    expect(
      screen.getByRole('heading', { name: 'Welcome to the Acme console' })
    ).toBeInTheDocument();
    expect(screen.getByText(/^It provides management/)).toBeInTheDocument();
    expect(screen.queryByText(/Acme console provides/)).not.toBeInTheDocument();
  });
});
