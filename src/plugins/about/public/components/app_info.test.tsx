/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { render, screen } from '@testing-library/react';
import { AboutAppInfo } from './app_info';

describe('AboutAppInfo', () => {
  it('shows the build', () => {
    render(<AboutAppInfo build="5.0.0-rc3-11" clusterUuid="abc" />);

    expect(screen.getByText(/App build:/)).toBeInTheDocument();
    expect(screen.getByText('5.0.0-rc3-11')).toBeInTheDocument();
  });

  it('shows the cluster UUID placeholder when there is none', () => {
    render(<AboutAppInfo build="5.0.0" />);

    expect(screen.getByText('-')).toBeInTheDocument();
  });

  it('shows a placeholder when the build is empty', () => {
    render(<AboutAppInfo build="" clusterUuid="abc" />);

    expect(screen.getByText(/App build:/)).toBeInTheDocument();
    expect(screen.getByText('-')).toBeInTheDocument();
  });
});
