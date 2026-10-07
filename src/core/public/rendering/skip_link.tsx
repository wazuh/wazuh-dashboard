/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { Observable } from 'rxjs';
import useObservable from 'react-use/lib/useObservable';
import { EuiSkipLink } from '@elastic/eui';
import { i18n } from '@osd/i18n';

const APP_WRAPPER_ID = 'app-wrapper';

const focusAppWrapper = (event: React.MouseEvent) => {
  // Apps route on the URL hash, so move focus instead of following `#app-wrapper`
  event.preventDefault();
  const appWrapper = document.getElementById(APP_WRAPPER_ID);
  if (!appWrapper) {
    return;
  }
  appWrapper.setAttribute('tabindex', '-1');
  appWrapper.addEventListener('blur', () => appWrapper.removeAttribute('tabindex'), {
    once: true,
  });
  appWrapper.focus();
};

export const SkipLink: React.FunctionComponent<{ chromeVisible$: Observable<boolean> }> = ({
  chromeVisible$,
}) => {
  const chromeVisible = useObservable(chromeVisible$);

  if (!chromeVisible) {
    return null;
  }

  return (
    <EuiSkipLink
      destinationId={APP_WRAPPER_ID}
      position="fixed"
      onClick={focusAppWrapper}
      data-test-subj="skipToMainContent"
    >
      {i18n.translate('core.ui.skipToMainContent', {
        defaultMessage: 'Skip to main content',
      })}
    </EuiSkipLink>
  );
};
