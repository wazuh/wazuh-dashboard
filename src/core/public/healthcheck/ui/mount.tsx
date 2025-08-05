/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import ReactDOM from 'react-dom';
import { HealthCheckNavButton } from './component';
import { formatDate } from './services/time';

export const mount = ({ coreStart, status$, fetch, run, computeCheckStatus, getConfig }) => {
  const isPlacedInLeftNav = coreStart.uiSettings.get('home:useNewHomePage');

  const formatDateWithClient = (date) => formatDate(coreStart.uiSettings, date);

  coreStart.chrome.navControls[isPlacedInLeftNav ? 'registerLeftBottom' : 'registerRight']({
    order: isPlacedInLeftNav ? 8999 : 1999,
    mount: (element: HTMLElement) => {
      ReactDOM.render(
        <HealthCheckNavButton
          coreStart={coreStart}
          status$={status$}
          fetch={fetch}
          run={run}
          getConfig={getConfig}
          formatDate={formatDateWithClient}
          computeCheckStatus={computeCheckStatus}
        />,
        element
      );
      return () => ReactDOM.unmountComponentAtNode(element);
    },
  });
};
