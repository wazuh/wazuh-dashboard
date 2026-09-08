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

import React from 'react';
import { createRoot } from 'react-dom/client';

import {
  EuiSmallButton,
  EuiButton,
  EuiCallOut,
  EuiCodeBlock,
  EuiModalBody,
  EuiModalFooter,
  EuiModalHeader,
  EuiModalHeaderTitle,
} from '@elastic/eui';
import { EuiSpacer } from '@elastic/eui';
import { FormattedMessage } from '@osd/i18n/react';
import { OverlayStart } from 'opensearch-dashboards/public';
import { I18nStart } from '../../i18n';

interface ErrorToastProps {
  title: string;
  error: Error;
  toastMessage: string;
  openModal: OverlayStart['openModal'];
  i18nContext: () => I18nStart['Context'];
}

// Wazuh: added root_cause, which the upstream type does not declare
interface ErrorDetail {
  type: string;
  reason: string;
}

interface RequestError extends Error {
  body?: {
    attributes?: {
      error?: {
        caused_by?: ErrorDetail;
        root_cause?: ErrorDetail[];
      };
    };
  };
}

// Wazuh: added the root cause of the failure and the redaction of the infrastructure
// details, from here down to redactInfrastructureDetails
const getBackendError = (error: Error | RequestError) =>
  'body' in error ? error.body?.attributes?.error : undefined;

/**
 * Returns the failure that actually made the request fail.
 *
 * `caused_by` can hold an unrelated failure raised while the response itself was being
 * built, which hides the actual cause, so the root cause is the detail worth showing as
 * the message of the dialog.
 */
const getRootCause = (error: Error | RequestError): ErrorDetail | undefined =>
  getBackendError(error)?.root_cause?.[0];

/**
 * Returns the technical detail of a backend error, shown in the copyable block.
 */
const getErrorDetail = (error: Error | RequestError): ErrorDetail | undefined => {
  const backendError = getBackendError(error);

  return backendError?.caused_by ?? backendError?.root_cause?.[0];
};

const REDACTED = '[redacted]';

/**
 * Infrastructure details that must not be exposed to the browser. Backend exception
 * reasons can carry the addresses and filesystem layout of the cluster, which are of
 * no use to the user and should not end up in a copyable block.
 */
const INFRASTRUCTURE_PATTERNS: RegExp[] = [
  // URLs, along with any credentials, host and port they carry
  /\b[a-z][a-z0-9+.-]*:\/\/\S+/gi,
  // IPv4 addresses, with an optional port
  /\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b/g,
  // IPv6 addresses. Three groups or more are required so that clock values such as
  // 10:30:45 are kept as they are
  /\b(?:[0-9a-f]{1,4})?(?::{1,2}[0-9a-f]{1,4}){3,}\b/gi,
  // Filesystem paths, anchored on the usual POSIX roots and on Windows drives
  /(?:[a-z]:\\|\/(?:usr|etc|var|opt|home|root|tmp|proc|mnt|srv|data)\/)[\w.\\/-]*/gi,
];

/**
 * Replaces the infrastructure details of a backend error message with a placeholder,
 * keeping the rest of the message readable.
 */
export function redactInfrastructureDetails(text: string): string {
  // The error is built by whoever throws it, so the message is not guaranteed to be
  // a string and the dialog must not fail while reporting another failure
  return INFRASTRUCTURE_PATTERNS.reduce(
    (redacted, pattern) => redacted.replace(pattern, REDACTED),
    String(text ?? '')
  );
}

/**
 * This should instead be replaced by the overlay service once it's available.
 * This does not use React portals so that if the parent toast times out, this modal
 * does not disappear. NOTE: this should use a global modal in the overlay service
 * in the future.
 */
function showErrorDialog({
  title,
  error,
  openModal,
  i18nContext,
}: Pick<ErrorToastProps, 'error' | 'title' | 'openModal' | 'i18nContext'>) {
  const I18nContext = i18nContext();
  // Wazuh
  const rootCause = getRootCause(error);
  const detail = getErrorDetail(error);
  let text = '';

  if (detail) {
    text += `${detail.type}\n`;
    text += `${detail.reason}\n\n`;
  }

  if (error.stack) {
    text += error.stack;
  }

  const modal = openModal(
    mount(
      <React.Fragment>
        <I18nContext>
          <EuiModalHeader>
            <EuiModalHeaderTitle>{title}</EuiModalHeaderTitle>
          </EuiModalHeader>
          <EuiModalBody>
            <EuiCallOut
              size="s"
              color="danger"
              iconType="alert"
              // Wazuh: redact the message before showing it
              title={redactInfrastructureDetails(error.message)}
            >
              {/* Wazuh: show the reason of the root cause, which caused_by can hide */}
              {rootCause && <p>{redactInfrastructureDetails(rootCause.reason)}</p>}
            </EuiCallOut>
            {text && (
              <React.Fragment>
                <EuiSpacer size="s" />
                <EuiCodeBlock isCopyable={true} paddingSize="s">
                  {text}
                </EuiCodeBlock>
              </React.Fragment>
            )}
          </EuiModalBody>
          <EuiModalFooter>
            <EuiSmallButton onClick={() => modal.close()} fill>
              <FormattedMessage
                id="core.notifications.errorToast.closeModal"
                defaultMessage="Close"
              />
            </EuiSmallButton>
          </EuiModalFooter>
        </I18nContext>
      </React.Fragment>
    )
  );
}

export function ErrorToast({
  title,
  error,
  toastMessage,
  openModal,
  i18nContext,
}: ErrorToastProps) {
  return (
    <React.Fragment>
      <p data-test-subj="errorToastMessage">{toastMessage}</p>
      <div className="eui-textRight">
        <EuiButton
          size="s"
          color="danger"
          onClick={() => showErrorDialog({ title, error, openModal, i18nContext })}
        >
          <FormattedMessage
            id="core.toasts.errorToast.seeFullError"
            defaultMessage="See the full error"
          />
        </EuiButton>
      </div>
    </React.Fragment>
  );
}

const mount = (component: React.ReactElement) => (container: HTMLElement) => {
  const root = createRoot(container);
  root.render(component);
  return () => root.unmount();
};
