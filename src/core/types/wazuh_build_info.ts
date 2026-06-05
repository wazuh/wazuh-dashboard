/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Wazuh build metadata exposed to plugins via injectedMetadata.
 *
 * @public
 */
export interface WazuhBuildInfo {
  version: string;
  revision: string;
  stage: string;
  isProduction: boolean;
}
