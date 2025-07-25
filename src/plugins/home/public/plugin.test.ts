/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * The OpenSearch Contributors require contributions made to
 * this file be licensed under the Apache-2.0 license or a
 * compatible open source license.
 *
 * Any modifications Copyright OpenSearch Contributors. See
 * GitHub history for details.
 */

/*
 * Licensed to Elasticsearch B.V. under one or more contributor
 * license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright
 * ownership. Elasticsearch B.V. licenses this file to you under
 * the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import { registryMock, environmentMock, tutorialMock, sectionTypeMock } from './plugin.test.mocks';
import { HomePublicPlugin } from './plugin';
import { coreMock } from '../../../core/public/mocks';
import { urlForwardingPluginMock } from '../../url_forwarding/public/mocks';
import { contentManagementPluginMocks } from 'src/plugins/content_management/public';

const mockInitializerContext = coreMock.createPluginInitializerContext();

describe('HomePublicPlugin', () => {
  beforeEach(() => {
    registryMock.setup.mockClear();
    registryMock.start.mockClear();
    tutorialMock.setup.mockClear();
    environmentMock.setup.mockClear();
    sectionTypeMock.setup.mockClear();
  });

  describe('setup', () => {
    test('registers tutorial directory to feature catalogue', async () => {
      const setup = await new HomePublicPlugin(mockInitializerContext).setup(
        coreMock.createSetup() as any,
        {
          urlForwarding: urlForwardingPluginMock.createSetupContract(),
          contentManagement: contentManagementPluginMocks.createSetupContract(),
        }
      );
      expect(setup).toHaveProperty('featureCatalogue');
      expect(setup.featureCatalogue.register).toHaveBeenCalledTimes(1);
      expect(setup.featureCatalogue.register).toHaveBeenCalledWith(
        expect.objectContaining({
          category: 'data',
          icon: 'indexOpen',
          id: 'home_tutorial_directory',
          showOnHomePage: false,
        })
      );
    });

    test('wires up and returns registry', async () => {
      const setup = await new HomePublicPlugin(mockInitializerContext).setup(
        coreMock.createSetup() as any,
        {
          urlForwarding: urlForwardingPluginMock.createSetupContract(),
          contentManagement: contentManagementPluginMocks.createSetupContract(),
        }
      );
      expect(setup).toHaveProperty('featureCatalogue');
      expect(setup.featureCatalogue).toHaveProperty('register');
    });

    test('wires up and returns environment service', async () => {
      const setup = await new HomePublicPlugin(mockInitializerContext).setup(
        coreMock.createSetup() as any,
        {
          urlForwarding: urlForwardingPluginMock.createSetupContract(),
          contentManagement: contentManagementPluginMocks.createSetupContract(),
        }
      );
      expect(setup).toHaveProperty('environment');
      expect(setup.environment).toHaveProperty('update');
    });

    test('wires up and returns tutorial service', async () => {
      const setup = await new HomePublicPlugin(mockInitializerContext).setup(
        coreMock.createSetup() as any,
        {
          urlForwarding: urlForwardingPluginMock.createSetupContract(),
          contentManagement: contentManagementPluginMocks.createSetupContract(),
        }
      );
      expect(setup).toHaveProperty('tutorials');
      expect(setup.tutorials).toHaveProperty('setVariable');
    });

    test('wires up and register applications', async () => {
      const coreMocks = coreMock.createSetup();
      await new HomePublicPlugin(mockInitializerContext).setup(coreMocks, {
        urlForwarding: urlForwardingPluginMock.createSetupContract(),
        contentManagement: contentManagementPluginMocks.createSetupContract(),
      });
      expect(coreMocks.application.register).toBeCalledTimes(2);
    });

    test('wires up and call addNavLinksToGroup if new navigation is enabled and workspace not enabled', async () => {
      const coreMocks = coreMock.createSetup();
      coreMocks.chrome.navGroup.getNavGroupEnabled.mockReturnValue(true);
      await new HomePublicPlugin(mockInitializerContext).setup(coreMocks, {
        urlForwarding: urlForwardingPluginMock.createSetupContract(),
        contentManagement: contentManagementPluginMocks.createSetupContract(),
      });
      expect(coreMocks.chrome.navGroup.addNavLinksToGroup).toBeCalledTimes(3);
    });
  });
});
