/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import { IndexPattern } from '../../../opensearch_dashboards_services';
import { buildColumns } from '../../utils/columns';
import { getIndexPatternFieldList } from '../../components/sidebar/lib/get_index_pattern_field_list';

/**
 * Helper function to filter columns based on the fields of the index pattern.
 * This function is used when we switch between index patterns. We want to keep the columns that are
 * still available in the new index pattern and remove the ones that are not.
 * If the resulting array is empty, it provides a fallback to the default column.
 * @param columns Array of column names
 * @param indexPattern Index pattern object
 * @param defaultColumns Array of default columns
 * @param modifyColumn Boolean of 'discover:modifyColumnsOnSwitch'
 * @param fieldCounts Number of times a field appears in results
 */
export function filterColumns(
  columns: string[],
  indexPattern: IndexPattern | undefined,
  defaultColumns: string[],
  modifyColumn: boolean,
  fieldCounts?: Record<string, number>
) {
  // if false, we keep all the chosen columns
  if (!modifyColumn) {
    return columns.length > 0 ? columns : ['_source'];
  }
  // if true, we keep columns that exist in the new index pattern
  const fieldsName = (fieldCounts
    ? getIndexPatternFieldList(indexPattern, fieldCounts)
    : indexPattern?.fields.getAll() || []
  ).map((fld) => fld.name);

  // combine columns and defaultColumns without duplicates
  const combinedColumns = [...new Set([...columns, ...defaultColumns])];
  const filteredColumns = combinedColumns.filter((column) => fieldsName.includes(column));
  const adjustedColumns = buildColumns(filteredColumns);
  return adjustedColumns.length > 0 ? adjustedColumns : ['_source'];
}
