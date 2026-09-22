/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * A single entry rendered in the persistent help menu / About page link
 * lists, configurable via `opensearch_dashboards.yml`.
 * @public
 */
export interface HelpMenuLinkItem {
  /** Text shown for the link. */
  label: string;
  /** URL the link points to. */
  link: string;
  /** Optional EUI iconType name or image URL rendered next to the label. */
  icon?: string;
  /** Optional icon used instead of `icon` when dark mode is enabled. Falls
   * back to `icon` when unset. */
  darkModeIcon?: string;
}
