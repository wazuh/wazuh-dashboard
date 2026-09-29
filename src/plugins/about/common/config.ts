/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { schema, TypeOf } from '@osd/config-schema';
import { DEFAULT_COMMUNITY_LINKS } from './constants';

const linkItemSchema = schema.object({
  label: schema.string(),
  link: schema.string(),
  icon: schema.maybe(schema.string()),
  darkModeIcon: schema.maybe(schema.string()),
});

export const configSchema = schema.object({
  // Replaces the whole default Slack/Google groups/Github list when set.
  communityLinks: schema.arrayOf(linkItemSchema, {
    defaultValue: DEFAULT_COMMUNITY_LINKS,
  }),
});

export type AboutConfigType = TypeOf<typeof configSchema>;
