/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import type { HelpMenuLinkItem } from '../../../core/types';

export const ABOUT_PLUGIN_ID = 'about';
export const ABOUT_APP_TITLE = 'About';
export const ABOUT_API_ROUTE = '/api/about';

// Default value of the `about.communityLinks` setting.
export const DEFAULT_COMMUNITY_LINKS: HelpMenuLinkItem[] = [
  { label: 'Slack', link: 'https://wazuh.com/community/join-us-on-slack/', icon: 'logoSlack' },
  {
    label: 'Google groups',
    link: 'https://groups.google.com/forum/#!forum/wazuh',
    icon: '/ui/logos/google_groups.svg',
  },
  {
    label: 'Github',
    link: 'https://github.com/wazuh/wazuh-dashboard-plugins',
    icon: 'logoGithub',
  },
];
