/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { render } from '@testing-library/react';
import { setServices } from '../opensearch_dashboards_services';
import { getMockedServices } from '../opensearch_dashboards_services.mock';
import { ImportSampleDataApp, HomeApp } from './home_app';

jest.mock('./legacy/home', () => ({
  Home: () => <div>Home</div>,
}));

jest.mock('../load_tutorials', () => ({
  getTutorial: () => {},
}));

jest.mock('./tutorial_directory', () => ({
  TutorialDirectory: (props: { withoutHomeBreadCrumb?: boolean }) => (
    <div
      data-test-subj="tutorial_directory"
      data-without-home-bread-crumb={!!props.withoutHomeBreadCrumb}
    />
  ),
}));

// Wazuh: skip this because we remove the sampledata and the tutorial because sample data is needed

describe.skip('<HomeApp />', () => {
  let currentService: ReturnType<typeof getMockedServices>;
  beforeEach(() => {
    currentService = getMockedServices();
    // @ts-ignore Error TS2345
    setServices(currentService);
  });

  it('should not pass withoutHomeBreadCrumb to TutorialDirectory component', async () => {
    const originalHash = window.location.hash;
    const { findByTestId } = render(<HomeApp />);
    window.location.hash = '/tutorial_directory';
    const tutorialRenderResult = await findByTestId('tutorial_directory');
    expect(tutorialRenderResult.dataset.withoutHomeBreadCrumb).toEqual('false');

    // revert to original hash
    window.location.hash = originalHash;
  });
});

describe.skip('<ImportSampleDataApp />', () => {
  let currentService: ReturnType<typeof getMockedServices>;
  beforeEach(() => {
    currentService = getMockedServices();
    // @ts-ignore Error TS2345
    setServices(currentService);
  });

  it('should pass withoutHomeBreadCrumb to TutorialDirectory component', async () => {
    const { findByTestId } = render(<ImportSampleDataApp />);
    const tutorialRenderResult = await findByTestId('tutorial_directory');
    expect(tutorialRenderResult.dataset.withoutHomeBreadCrumb).toEqual('true');
  });
});
