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
import wazuh from '../../../../package.json';

export const WAZUH_MAJOR = wazuh.wazuh.version.split('.')[0];
export const WAZUH_MINOR = wazuh.wazuh.version.split('.')[1];

export const OPENSEARCH_DASHBOARDS_FEEDBACK_LINK = 'https://wazuh.com/community/join-us-on-slack';
export const OPENSEARCH_DASHBOARDS_ASK_OPENSEARCH_LINK = OPENSEARCH_DASHBOARDS_FEEDBACK_LINK;
export const GITHUB_CREATE_ISSUE_LINK = 'https://github.com/wazuh/wazuh/issues/new/choose';

export enum RightNavigationOrder {
  // order of dev tool should be after advance settings
  Settings = 10,
  DevTool = 20,
}

export enum HeaderControlsContainer {
  LEFT = 'left',
  CENTER = 'center',
  RIGHT = 'right',
  BADGE = 'badge',
  DESCRIPTION = 'description',
  BOTTOM = 'bottom',
}

export enum HeaderVariant {
  PAGE = 'page',
  APPLICATION = 'application',
}
export const WAZUH_DOCUMENTATION_URL = `https://documentation.wazuh.com/${WAZUH_MAJOR}.${WAZUH_MINOR}/`;
