/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import ReactDOM from 'react-dom';
import { HealthCheckNavButton, HealthCheckNavButtonProps } from './component';
import { formatDate } from './services/time';

export const mount = ({
  coreStart,
  status$,
  fetch,
  run,
  getConfig,
}: Omit<HealthCheckNavButtonProps, 'formatDate'>) => {
  const isPlacedInLeftNav = coreStart.uiSettings.get('home:useNewHomePage');

  const formatDateWithClient = (date: string) => formatDate(coreStart.uiSettings, date);

  coreStart.chrome.navControls[isPlacedInLeftNav ? 'registerLeftBottom' : 'registerRight']({
    order: isPlacedInLeftNav ? 9999 : 2002,
    mount: (element: HTMLElement) => {
      ReactDOM.render(
        <HealthCheckNavButton
          coreStart={coreStart}
          status$={status$}
          fetch={fetch}
          run={run}
          getConfig={getConfig}
          formatDate={formatDateWithClient}
        />,
        element
      );
      return () => ReactDOM.unmountComponentAtNode(element);
    },
  });
};
