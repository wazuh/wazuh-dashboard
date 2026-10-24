/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import { i18n } from '@osd/i18n';

interface QuickRangeLabel {
  from: string;
  to: string;
  id: string;
  defaultMessage: string;
}

/**
 * Default timepicker:quickRanges from data.advancedSettings.timepicker.*.
 * Labels are stored in uiSettings as English on first write; re-translate at render.
 */
const QUICK_RANGE_LABELS: QuickRangeLabel[] = [
  {
    from: 'now/d',
    to: 'now/d',
    id: 'data.advancedSettings.timepicker.today',
    defaultMessage: 'Today',
  },
  {
    from: 'now/w',
    to: 'now/w',
    id: 'data.advancedSettings.timepicker.thisWeek',
    defaultMessage: 'This week',
  },
  {
    from: 'now-15m',
    to: 'now',
    id: 'data.advancedSettings.timepicker.last15Minutes',
    defaultMessage: 'Last 15 minutes',
  },
  {
    from: 'now-30m',
    to: 'now',
    id: 'data.advancedSettings.timepicker.last30Minutes',
    defaultMessage: 'Last 30 minutes',
  },
  {
    from: 'now-1h',
    to: 'now',
    id: 'data.advancedSettings.timepicker.last1Hour',
    defaultMessage: 'Last 1 hour',
  },
  {
    from: 'now-24h',
    to: 'now',
    id: 'data.advancedSettings.timepicker.last24Hours',
    defaultMessage: 'Last 24 hours',
  },
  {
    from: 'now-7d',
    to: 'now',
    id: 'data.advancedSettings.timepicker.last7Days',
    defaultMessage: 'Last 7 days',
  },
  {
    from: 'now-30d',
    to: 'now',
    id: 'data.advancedSettings.timepicker.last30Days',
    defaultMessage: 'Last 30 days',
  },
  {
    from: 'now-90d',
    to: 'now',
    id: 'data.advancedSettings.timepicker.last90Days',
    defaultMessage: 'Last 90 days',
  },
  {
    from: 'now-1y',
    to: 'now',
    id: 'data.advancedSettings.timepicker.last1Year',
    defaultMessage: 'Last 1 year',
  },
];

const byFromTo = new Map(QUICK_RANGE_LABELS.map((range) => [`${range.from}|${range.to}`, range]));
const byDisplay = new Map(QUICK_RANGE_LABELS.map((range) => [range.defaultMessage, range]));

export function translateQuickRangeLabel(from: string, to: string, display: string): string {
  const match = byFromTo.get(`${from}|${to}`) || byDisplay.get(display);
  if (!match) {
    return display;
  }
  return i18n.translate(match.id, { defaultMessage: match.defaultMessage });
}

export function toDatePickerLocale(osdLocale?: string): string {
  const locale =
    osdLocale || (typeof i18n.getLocale === 'function' ? i18n.getLocale() : 'en') || 'en';
  const lower = locale.toLowerCase();
  if (lower.startsWith('ru')) {
    return 'ru';
  }
  if (lower === 'zh-cn' || lower.startsWith('zh-cn')) {
    return 'zh-cn';
  }
  if (lower === 'zh-tw' || lower.startsWith('zh-tw')) {
    return 'zh-tw';
  }
  return locale.split('-')[0] || 'en';
}
