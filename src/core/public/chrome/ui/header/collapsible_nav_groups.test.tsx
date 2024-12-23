/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { fireEvent, render } from '@testing-library/react';
import { NavGroups } from './collapsible_nav_groups';
import { ChromeRegistrationNavLink } from '../../nav_group';
import { ChromeNavLink } from '../../nav_links';

describe('<NavGroups />', () => {
  const getMockedNavLink = (
    navLink: Partial<ChromeNavLink & ChromeRegistrationNavLink>
  ): ChromeNavLink & ChromeRegistrationNavLink => ({
    baseUrl: '',
    href: '',
    id: '',
    title: '',
    ...navLink,
  });
  it('should render correctly', () => {
    const navigateToApp = jest.fn();
    const onNavItemClick = jest.fn();
    const { container, getByTestId, queryByTestId } = render(
      <NavGroups
        navLinks={[
          getMockedNavLink({
            id: 'pure',
            title: 'pure link',
          }),
          getMockedNavLink({
            id: 'subLink',
            title: 'subLink',
            parentNavLinkId: 'pure',
          }),
          getMockedNavLink({
            id: 'link-in-category',
            title: 'link-in-category',
            category: {
              id: 'category-1',
              label: 'category-1',
            },
          }),
          getMockedNavLink({
            id: 'link-2-in-category',
            title: 'link-2-in-category',
            category: {
              id: 'category-1',
              label: 'category-1',
            },
          }),
          getMockedNavLink({
            id: 'sub-link-in-category',
            title: 'sub-link-in-category',
            parentNavLinkId: 'link-in-category',
            category: {
              id: 'category-1',
              label: 'category-1',
            },
          }),
        ]}
        navigateToApp={navigateToApp}
        onNavItemClick={onNavItemClick}
      />
    );
    // Wazuh: Changes of the test because the menu starts collapsed
    expect(container).toMatchSnapshot();
    // The accordion is collapsed by default
    expect(container.querySelectorAll('.nav-link-item-btn').length).toEqual(3);
    expect(queryByTestId('collapsibleNavAppLink-subLink')).toBeNull();
    fireEvent.click(getByTestId('collapsibleNavAppLink-pure'));
    expect(navigateToApp).toBeCalledTimes(0);
    // Expand the accordion
    expect(queryByTestId('collapsibleNavAppLink-subLink')).toBeInTheDocument();
    fireEvent.click(getByTestId('collapsibleNavAppLink-subLink'));
    expect(navigateToApp).toBeCalledWith('subLink');
  });
});
