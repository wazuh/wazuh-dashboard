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

import {
  EuiSmallButton,
  EuiSmallButtonEmpty,
  EuiButtonEmpty,
  // @ts-ignore
  EuiCodeEditor,
  EuiCompressedFieldText,
  EuiFlexGroup,
  EuiFlexItem,
  EuiForm,
  EuiCompressedFormRow,
  EuiPopoverTitle,
  EuiSpacer,
  EuiCompressedSwitch,
  EuiSwitchEvent,
} from '@elastic/eui';
import { i18n } from '@osd/i18n';
import { FormattedMessage, InjectedIntl, injectI18n } from '@osd/i18n/react';
import { get } from 'lodash';
import React, { Component } from 'react';
import { parse, stringify } from '@osd/std';
import { GenericComboBox, GenericComboBoxProps } from './generic_combo_box';
import {
  getFieldFromFilter,
  getFilterableFields,
  getOperatorFromFilter,
  getOperatorOptions,
  isFilterValid,
} from './lib/filter_editor_utils';
import { Operator } from './lib/filter_operators';
import { PhraseValueInput } from './phrase_value_input';
import { PhrasesValuesInput } from './phrases_values_input';
import { RangeValueInput } from './range_value_input';
import { IIndexPattern, IFieldType } from '../../..';
import {
  Filter,
  getIndexPatternFromFilter,
  FieldFilter,
  buildFilter,
  buildCustomFilter,
  cleanFilter,
  getFilterParams,
} from '../../../../common';

interface Props {
  filter: Filter;
  indexPatterns: IIndexPattern[];
  onSubmit: (filter: Filter) => void;
  onCancel: () => void;
  intl: InjectedIntl;
}

interface State {
  selectedIndexPattern?: IIndexPattern;
  selectedField?: IFieldType;
  selectedOperator?: Operator;
  params: any;
  useCustomLabel: boolean;
  customLabel: string | null;
  queryDsl: string;
  isCustomEditorOpen: boolean;
}

class FilterEditorUI extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      selectedIndexPattern: this.getIndexPatternFromFilter(),
      selectedField: this.getFieldFromFilter(),
      selectedOperator: this.getSelectedOperator(),
      params: getFilterParams(props.filter),
      useCustomLabel: props.filter.meta.alias !== null,
      customLabel: props.filter.meta.alias,
      queryDsl: stringify(cleanFilter(props.filter), null, 2),
      isCustomEditorOpen: this.isUnknownFilterType(),
    };
  }

  public render() {
    return (
      <div>
        <EuiPopoverTitle paddingSize="s">
          <EuiFlexGroup alignItems="baseline" responsive={false}>
            <EuiFlexItem>
              <FormattedMessage
                id="data.filter.filterEditor.editFilterPopupTitle"
                defaultMessage="Edit filter"
              />
            </EuiFlexItem>
            <EuiFlexItem grow={false} className="filterEditor__hiddenItem" />
            <EuiFlexItem grow={false}>
              <EuiButtonEmpty
                size="xs"
                data-test-subj="editQueryDSL"
                onClick={this.toggleCustomEditor}
              >
                {this.state.isCustomEditorOpen ? (
                  <FormattedMessage
                    id="data.filter.filterEditor.editFilterValuesButtonLabel"
                    defaultMessage="Edit filter values"
                  />
                ) : (
                  <FormattedMessage
                    id="data.filter.filterEditor.editQueryDslButtonLabel"
                    defaultMessage="Edit as Query DSL"
                  />
                )}
              </EuiButtonEmpty>
            </EuiFlexItem>
          </EuiFlexGroup>
        </EuiPopoverTitle>

        <div className="globalFilterItem__editorForm" data-test-subj="globalFilterItemEditor">
          <EuiForm>
            {this.renderIndexPatternInput()}

            {this.state.isCustomEditorOpen ? this.renderCustomEditor() : this.renderRegularEditor()}

            <EuiSpacer size="m" />

            <EuiCompressedSwitch
              id="filterEditorCustomLabelSwitch"
              data-test-subj="createCustomLabel"
              label={this.props.intl.formatMessage({
                id: 'data.filter.filterEditor.createCustomLabelSwitchLabel',
                defaultMessage: 'Create custom label?',
              })}
              checked={this.state.useCustomLabel}
              onChange={this.onCustomLabelSwitchChange}
            />

            {this.state.useCustomLabel && (
              <div>
                <EuiSpacer size="m" />
                <EuiCompressedFormRow
                  fullWidth={true}
                  label={this.props.intl.formatMessage({
                    id: 'data.filter.filterEditor.createCustomLabelInputLabel',
                    defaultMessage: 'Custom label',
                  })}
                >
                  <EuiCompressedFieldText
                    fullWidth={true}
                    value={`${this.state.customLabel}`}
                    onChange={this.onCustomLabelChange}
                  />
                </EuiCompressedFormRow>
              </div>
            )}

            <EuiSpacer size="m" />

            <EuiFlexGroup direction="rowReverse" alignItems="center" responsive={false}>
              <EuiFlexItem grow={false}>
                <EuiSmallButton
                  fill
                  onClick={this.onSubmit}
                  isDisabled={!this.isFilterValid()}
                  data-test-subj="saveFilter"
                >
                  <FormattedMessage
                    id="data.filter.filterEditor.saveButtonLabel"
                    defaultMessage="Save"
                  />
                </EuiSmallButton>
              </EuiFlexItem>
              <EuiFlexItem grow={false}>
                <EuiSmallButtonEmpty
                  flush="right"
                  onClick={this.props.onCancel}
                  data-test-subj="cancelSaveFilter"
                >
                  <FormattedMessage
                    id="data.filter.filterEditor.cancelButtonLabel"
                    defaultMessage="Cancel"
                  />
                </EuiSmallButtonEmpty>
              </EuiFlexItem>
              <EuiFlexItem />
            </EuiFlexGroup>
          </EuiForm>
        </div>
      </div>
    );
  }

  private renderIndexPatternInput() {
    if (
      this.props.indexPatterns.length <= 1 &&
      this.props.indexPatterns.find(
        (indexPattern) => indexPattern === this.getIndexPatternFromFilter()
      )
    ) {
      /**
       * Don't render the index pattern selector if there's just one \ zero index patterns
       * and if the index pattern the filter was LOADED with is in the indexPatterns list.
       **/

      return '';
    }
    const { selectedIndexPattern } = this.state;
    return (
      <EuiFlexGroup>
        <EuiFlexItem>
          <EuiCompressedFormRow
            label={this.props.intl.formatMessage({
              id: 'data.filter.filterEditor.indexPatternSelectLabel',
              defaultMessage: 'Index Pattern',
            })}
          >
            <IndexPatternComboBox
              placeholder={this.props.intl.formatMessage({
                id: 'data.filter.filterBar.indexPatternSelectPlaceholder',
                defaultMessage: 'Select an index pattern',
              })}
              options={this.props.indexPatterns}
              selectedOptions={selectedIndexPattern ? [selectedIndexPattern] : []}
              getLabel={(indexPattern) => indexPattern.title}
              onChange={this.onIndexPatternChange}
              singleSelection={{ asPlainText: true }}
              isClearable={false}
              data-test-subj="filterIndexPatternsSelect"
            />
          </EuiCompressedFormRow>
        </EuiFlexItem>
      </EuiFlexGroup>
    );
  }

  private renderRegularEditor() {
    return (
      <div>
        <EuiFlexGroup responsive={false} gutterSize="s">
          <EuiFlexItem grow={2}>{this.renderFieldInput()}</EuiFlexItem>
          <EuiFlexItem grow={false} style={{ flexBasis: 160 }}>
            {this.renderOperatorInput()}
          </EuiFlexItem>
        </EuiFlexGroup>
        <EuiSpacer size="s" />
        <div data-test-subj="filterParams">{this.renderParamsEditor()}</div>
      </div>
    );
  }

  private renderFieldInput() {
    const { selectedIndexPattern, selectedField } = this.state;
    const fields = selectedIndexPattern ? getFilterableFields(selectedIndexPattern) : [];

    return (
      <EuiCompressedFormRow
        label={this.props.intl.formatMessage({
          id: 'data.filter.filterEditor.fieldSelectLabel',
          defaultMessage: 'Field',
        })}
      >
        <FieldComboBox
          id="fieldInput"
          fullWidth={true}
          isDisabled={!selectedIndexPattern}
          placeholder={this.props.intl.formatMessage({
            id: 'data.filter.filterEditor.fieldSelectPlaceholder',
            defaultMessage: 'Select a field first',
          })}
          options={fields}
          selectedOptions={selectedField ? [selectedField] : []}
          getLabel={(field) => field.name}
          onChange={this.onFieldChange}
          singleSelection={{ asPlainText: true }}
          isClearable={false}
          className="globalFilterEditor__fieldInput"
          data-test-subj="filterFieldSuggestionList"
        />
      </EuiCompressedFormRow>
    );
  }

  private renderOperatorInput() {
    const { selectedField, selectedOperator } = this.state;
    const operators = selectedField ? getOperatorOptions(selectedField) : [];
    return (
      <EuiCompressedFormRow
        label={this.props.intl.formatMessage({
          id: 'data.filter.filterEditor.operatorSelectLabel',
          defaultMessage: 'Operator',
        })}
      >
        <OperatorComboBox
          isDisabled={!selectedField}
          placeholder={
            selectedField
              ? this.props.intl.formatMessage({
                  id: 'data.filter.filterEditor.operatorSelectPlaceholderSelect',
                  defaultMessage: 'Select',
                })
              : this.props.intl.formatMessage({
                  id: 'data.filter.filterEditor.operatorSelectPlaceholderWaiting',
                  defaultMessage: 'Waiting',
                })
          }
          options={operators}
          selectedOptions={selectedOperator ? [selectedOperator] : []}
          getLabel={({ message }) => message}
          onChange={this.onOperatorChange}
          singleSelection={{ asPlainText: true }}
          isClearable={false}
          data-test-subj="filterOperatorList"
        />
      </EuiCompressedFormRow>
    );
  }

  private renderCustomEditor() {
    return (
      <EuiCompressedFormRow
        label={i18n.translate('data.filter.filterEditor.queryDslLabel', {
          defaultMessage: 'OpenSearch Query DSL',
        })}
        fullWidth={true}
      >
        <EuiCodeEditor
          value={this.state.queryDsl}
          onChange={this.onQueryDslChange}
          mode="json"
          width="100%"
          height="250px"
        />
      </EuiCompressedFormRow>
    );
  }

  private renderParamsEditor() {
    const indexPattern = this.state.selectedIndexPattern;
    if (!indexPattern || !this.state.selectedOperator) {
      return '';
    }

    switch (this.state.selectedOperator.type) {
      case 'exists':
        return '';
      case 'phrase':
        return (
          <PhraseValueInput
            indexPattern={indexPattern}
            field={this.state.selectedField}
            value={this.state.params}
            onChange={this.onParamsChange}
            data-test-subj="phraseValueInput"
          />
        );
      case 'phrases':
        return (
          <PhrasesValuesInput
            indexPattern={indexPattern}
            field={this.state.selectedField}
            values={this.state.params}
            onChange={this.onParamsChange}
          />
        );
      case 'range':
        return (
          <RangeValueInput
            field={this.state.selectedField}
            value={this.state.params}
            onChange={this.onParamsChange}
          />
        );
    }
  }

  private toggleCustomEditor = () => {
    const isCustomEditorOpen = !this.state.isCustomEditorOpen;
    this.setState({ isCustomEditorOpen });
  };

  private isUnknownFilterType() {
    const { type } = this.props.filter.meta;
    return !!type && !['phrase', 'phrases', 'range', 'exists'].includes(type);
  }

  private getIndexPatternFromFilter() {
    return getIndexPatternFromFilter(this.props.filter, this.props.indexPatterns);
  }

  private getFieldFromFilter() {
    const indexPattern = this.getIndexPatternFromFilter();
    return indexPattern && getFieldFromFilter(this.props.filter as FieldFilter, indexPattern);
  }

  private getSelectedOperator() {
    return getOperatorFromFilter(this.props.filter);
  }

  private isFilterValid() {
    const {
      isCustomEditorOpen,
      queryDsl,
      selectedIndexPattern: indexPattern,
      selectedField: field,
      selectedOperator: operator,
      params,
    } = this.state;

    if (isCustomEditorOpen) {
      try {
        return Boolean(parse(queryDsl));
      } catch (e) {
        return false;
      }
    }

    return isFilterValid(indexPattern, field, operator, params);
  }

  private onIndexPatternChange = ([selectedIndexPattern]: IIndexPattern[]) => {
    const selectedField = undefined;
    const selectedOperator = undefined;
    const params = undefined;
    this.setState({ selectedIndexPattern, selectedField, selectedOperator, params });
  };

  private onFieldChange = ([selectedField]: IFieldType[]) => {
    const selectedOperator = undefined;
    const params = undefined;
    this.setState({ selectedField, selectedOperator, params });
  };

  private onOperatorChange = ([selectedOperator]: Operator[]) => {
    // Only reset params when the operator type changes
    const params =
      get(this.state.selectedOperator, 'type') === get(selectedOperator, 'type')
        ? this.state.params
        : undefined;
    this.setState({ selectedOperator, params });
  };

  private onCustomLabelSwitchChange = (event: EuiSwitchEvent) => {
    const useCustomLabel = event.target.checked;
    const customLabel = event.target.checked ? '' : null;
    this.setState({ useCustomLabel, customLabel });
  };

  private onCustomLabelChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const customLabel = event.target.value;
    this.setState({ customLabel });
  };

  private onParamsChange = (params: any) => {
    this.setState({ params });
  };

  private onQueryDslChange = (queryDsl: string) => {
    this.setState({ queryDsl });
  };

  private onSubmit = () => {
    const {
      selectedIndexPattern: indexPattern,
      selectedField: field,
      selectedOperator: operator,
      params,
      useCustomLabel,
      customLabel,
      isCustomEditorOpen,
      queryDsl,
    } = this.state;

    const { $state } = this.props.filter;
    if (!$state || !$state.store) {
      return; // typescript validation
    }
    const alias = useCustomLabel ? customLabel : null;

    if (isCustomEditorOpen) {
      const { index, disabled, negate } = this.props.filter.meta;
      const newIndex = index || this.props.indexPatterns[0].id!;
      const body = parse(queryDsl);
      const filter = buildCustomFilter(newIndex, body, disabled, negate, alias, $state.store);
      this.props.onSubmit(filter);
    } else if (indexPattern && field && operator) {
      const filter = buildFilter(
        indexPattern,
        field,
        operator.type,
        operator.negate,
        this.props.filter.meta.disabled,
        params ?? '',
        alias,
        $state.store
      );
      this.props.onSubmit(filter);
    }
  };
}

function IndexPatternComboBox(props: GenericComboBoxProps<IIndexPattern>) {
  return GenericComboBox(props);
}

function FieldComboBox(props: GenericComboBoxProps<IFieldType>) {
  return GenericComboBox(props);
}

function OperatorComboBox(props: GenericComboBoxProps<Operator>) {
  return GenericComboBox(props);
}

export const FilterEditor = injectI18n(FilterEditorUI);
