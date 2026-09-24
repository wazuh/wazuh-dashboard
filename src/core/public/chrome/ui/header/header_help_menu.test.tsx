/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { BehaviorSubject } from 'rxjs';
import { mountWithIntl } from 'test_utils/enzyme_helpers';
import { HeaderHelpMenu } from './header_help_menu';

function mockProps() {
  return {
    helpExtension$: new BehaviorSubject(undefined),
    helpSupportUrl$: new BehaviorSubject(''),
    opensearchDashboardsDocLink: '/doclink',
    opensearchDashboardsVersion: '1.0',
    useDefaultContent: true,
    darkmode: false,
  };
}

describe('Header help menu', () => {
  it('renders survey link', () => {
    const props = {
      ...mockProps(),
      surveyLink: '/',
    };
    const component = mountWithIntl(<HeaderHelpMenu {...props} />);
    component.find('button').simulate('click');

    expect(component).toMatchSnapshot();
  });

  it('hides survey link', () => {
    const props = {
      ...mockProps(),
      surveyLink: '',
    };
    const component = mountWithIntl(<HeaderHelpMenu {...props} />);
    component.find('button').simulate('click');

    expect(component).toMatchSnapshot();
  });

  describe('configured links', () => {
    const SLACK_URL = 'https://wazuh.com/community/join-us-on-slack/';

    const mountAndOpen = (links?: Array<{ label: string; link: string }>) => {
      const component = mountWithIntl(<HeaderHelpMenu {...mockProps()} links={links} />);
      component.find('button').simulate('click');
      return component;
    };

    it('renders the built-in links when unset', () => {
      const component = mountAndOpen(undefined);

      expect(component.find(`a[href="${SLACK_URL}"]`).exists()).toBe(true);
    });

    it('renders no links when configured as an empty list', () => {
      const component = mountAndOpen([]);

      expect(component.find(`a[href="${SLACK_URL}"]`).exists()).toBe(false);
      expect(component.find('a[href^="https://groups.google.com"]').exists()).toBe(false);
    });

    it('replaces the built-in links with the configured ones', () => {
      const component = mountAndOpen([{ label: 'Custom', link: 'https://example.com' }]);

      const customLink = component.find('a[href="https://example.com"]');
      expect(customLink.exists()).toBe(true);
      expect(customLink.text()).toBe('Custom');
      expect(component.find(`a[href="${SLACK_URL}"]`).exists()).toBe(false);
    });
  });
});
