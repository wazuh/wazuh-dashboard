/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { BehaviorSubject } from 'rxjs';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { SkipLink } from './skip_link';

const renderWithAppWrapper = (chromeVisible$: BehaviorSubject<boolean>) =>
  render(
    <>
      <SkipLink chromeVisible$={chromeVisible$} />
      <div id="app-wrapper">
        <button>First app control</button>
      </div>
    </>
  );

describe('SkipLink', () => {
  it('renders a link to the app wrapper while the chrome is visible', () => {
    renderWithAppWrapper(new BehaviorSubject<boolean>(true));

    const skipLink = screen.getByTestId('skipToMainContent');
    expect(skipLink).toHaveTextContent('Skip to main content');
    expect(skipLink).toHaveAttribute('href', '#app-wrapper');
  });

  it('renders nothing while the chrome is hidden', () => {
    const chromeVisible$ = new BehaviorSubject<boolean>(false);
    renderWithAppWrapper(chromeVisible$);
    expect(screen.queryByTestId('skipToMainContent')).toBeNull();

    act(() => chromeVisible$.next(true));
    expect(screen.queryByTestId('skipToMainContent')).not.toBeNull();
  });

  it('moves focus to the app wrapper without changing the URL hash', () => {
    window.location.hash = '#/overview';
    renderWithAppWrapper(new BehaviorSubject<boolean>(true));
    const appWrapper = document.getElementById('app-wrapper')!;

    const notPrevented = fireEvent.click(screen.getByTestId('skipToMainContent'));

    expect(notPrevented).toBe(false);
    expect(window.location.hash).toBe('#/overview');
    expect(appWrapper).toHaveFocus();
    expect(appWrapper).toHaveAttribute('tabindex', '-1');

    act(() => screen.getByText('First app control').focus());
    expect(appWrapper).not.toHaveAttribute('tabindex');
  });
});
