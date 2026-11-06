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

import { shallow } from 'enzyme';
import React from 'react';
import { act } from 'react-dom/test-utils';
import { mountWithIntl } from 'test_utils/enzyme_helpers';

import { ErrorToast, redactInfrastructureDetails } from './error_toast';

interface ErrorToastProps {
  error?: Error;
  title?: string;
  toastMessage?: string;
}

let openModal: jest.Mock;

beforeEach(() => (openModal = jest.fn()));

function render(props: ErrorToastProps = {}) {
  return (
    <ErrorToast
      openModal={openModal}
      error={props.error || new Error('error message')}
      title={props.title || 'An error occured'}
      toastMessage={props.toastMessage || 'This is the toast message'}
      i18nContext={() => ({ children }) => <React.Fragment>{children}</React.Fragment>}
    />
  );
}

it('renders matching snapshot', () => {
  expect(shallow(render())).toMatchSnapshot();
});

it('should open a modal when clicking button', () => {
  const wrapper = mountWithIntl(render());
  expect(openModal).not.toHaveBeenCalled();
  wrapper.find('button').simulate('click');
  expect(openModal).toHaveBeenCalled();
});

describe('redactInfrastructureDetails', () => {
  it('redacts URLs, including the bundle URLs of the client', () => {
    expect(
      redactInfrastructureDetails(
        'failed at https://dashboard.internal:5601/bundles/plugin/data/data.chunk.1.js'
      )
    ).toBe('failed at [redacted]');
  });

  it('redacts IPv4 addresses with and without a port', () => {
    expect(
      redactInfrastructureDetails('node [wazuh-indexer-1] at 10.0.13.7:9200 and 192.168.1.24')
    ).toBe('node [wazuh-indexer-1] at [redacted] and [redacted]');
  });

  it('redacts IPv6 addresses but keeps clock values', () => {
    expect(
      redactInfrastructureDetails('2001:0db8:85a3:0000:0000:8a2e:0370:7334 failed at 10:30:45')
    ).toBe('[redacted] failed at 10:30:45');
  });

  it('redacts POSIX and Windows filesystem paths', () => {
    expect(
      redactInfrastructureDetails(
        'cannot read /usr/share/wazuh-indexer/data/nodes/0 nor C:\\indexer\\data'
      )
    ).toBe('cannot read [redacted] nor [redacted]');
  });

  it('keeps a message without infrastructure details as it is', () => {
    expect(
      redactInfrastructureDetails('Cannot search on field [event.original] since it is not indexed')
    ).toBe('Cannot search on field [event.original] since it is not indexed');
  });
});

describe('showErrorDialog', () => {
  const openDialog = async (error: Error) => {
    const wrapper = mountWithIntl(render({ error }));
    wrapper.find('button').simulate('click');

    const container = document.createElement('div');
    await act(async () => {
      openModal.mock.calls[0][0](container);
    });

    return container.textContent || '';
  };

  it('renders the stack trace of the error in the copyable block', async () => {
    const error = new Error('Search Error');
    error.stack = 'Error: Search Error\n    at Fetch.<anonymous> (http://localhost:5601/bundle.js)';

    const text = await openDialog(error);

    expect(text).toContain('Search Error');
    expect(text).toContain('Fetch.<anonymous>');
  });

  it('shows the root cause reason above the technical detail', async () => {
    const error: Error & { body?: unknown } = new Error('Bad Request');
    error.body = {
      attributes: {
        error: {
          type: 'search_phase_execution_exception',
          reason: '',
          root_cause: [
            {
              type: 'query_shard_exception',
              reason:
                'failed to create query: Cannot search on field [event.original] since it is both not indexed, and does not have doc_values enabled.',
            },
          ],
          caused_by: {
            type: 'null_pointer_exception',
            reason:
              'Cannot invoke "org.opensearch.search.aggregations.InternalAggregations.getSerializedSize()" because "reducePhase.aggregations" is null',
          },
        },
      },
    };

    const text = await openDialog(error);

    // The root cause is the message of the dialog, the caused by failure of the response
    // stays in the copyable block below it
    expect(text.indexOf('Cannot search on field [event.original]')).toBeGreaterThan(-1);
    expect(text.indexOf('Cannot search on field [event.original]')).toBeLessThan(
      text.indexOf('null_pointer_exception')
    );
    expect(text).toContain('reducePhase.aggregations');
  });

  it('falls back to the caused by detail when there is no root cause', async () => {
    const error: Error & { body?: unknown } = new Error('Bad Request');
    error.body = {
      attributes: {
        error: {
          caused_by: {
            type: 'illegal_argument_exception',
            reason: 'text is analyzed',
          },
        },
      },
    };

    const text = await openDialog(error);

    expect(text).toContain('illegal_argument_exception');
    expect(text).toContain('text is analyzed');
  });

  it('redacts the infrastructure details of the root cause reason', async () => {
    const error: Error & { body?: unknown } = new Error('Search Error');
    error.body = {
      attributes: {
        error: {
          root_cause: [
            {
              type: 'query_shard_exception',
              reason: 'failed to create query on node 10.0.13.7:9200',
            },
          ],
        },
      },
    };

    const text = await openDialog(error);

    // The callout redacts the reason, while the copyable block keeps the payload of the
    // backend and the stack trace as they are
    expect(text).toContain('failed to create query on node [redacted]');
    expect(text).toContain('failed to create query on node 10.0.13.7:9200');
  });
});

afterAll(() => {
  // Cleanup document.body to cleanup any modals which might be left over from tests.
  document.body.innerHTML = '';
});
