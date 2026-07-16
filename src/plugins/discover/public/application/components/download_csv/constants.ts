/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * The upper limit option of the "Max" download option.
 * Used as the fallback default when the `reports.csv.maxRows` setting is not
 * available.
 */
export const MAX_DOWNLOAD_CSV_COUNT = 10000;

/**
 * uiSetting that defines the maximum number of rows included when downloading a
 * CSV. It is shared across the Wazuh dashboard plugins so the CSV export limit
 * stays consistent. Registered by the wazuh-core plugin.
 */
export const REPORTS_CSV_MAX_ROWS_SETTING = 'reports.csv.maxRows';

/**
 * The available export options:
 * - Visible = download the current queried result
 * - Max = download Math.min(hits, reports.csv.maxRows)
 */
export enum DownloadCsvFormId {
  Visible = 'visible',
  Max = 'max',
}
