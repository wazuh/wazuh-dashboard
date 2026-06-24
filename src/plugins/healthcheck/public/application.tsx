/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { createRoot } from 'react-dom/client';
import { AppMountParameters, CoreStart } from '../../../core/public';
import { AppPluginStartDependencies } from './types';
import { HealtcheckApp } from './components/app';

export const renderApp = (
  { notifications, http }: CoreStart,
  { navigation }: AppPluginStartDependencies,
  { appBasePath, element }: AppMountParameters
) => {
  const root = createRoot(element);

  root.render(
    <HealtcheckApp
      basename={appBasePath}
      notifications={notifications}
      http={http}
      navigation={navigation}
    />
  );

  return () => root.unmount();
};
