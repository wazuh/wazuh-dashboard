/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Builds the default revision shown in the About page: `<stage>-<revision>`.
 * When only one of them is available, that one is returned on its own.
 */
export const formatRevision = (stage?: string, revision?: string): string => {
  if (stage && revision) {
    return `${stage}-${revision}`;
  }
  return stage || revision || '';
};

interface FormatBuildParams {
  /** Version of the build. */
  version: string;
  /** Stage of the build, e.g. `rc3`. */
  stage?: string;
  /** Revision number of the build. */
  revision?: string;
  /** `opensearchDashboards.branding.applicationVersion`, when defined. */
  versionOverride?: string;
}

/**
 * Builds the build label shown in the About page.
 *
 * - `applicationVersion` defined (an empty string is valid): it is used as the build, as is.
 * - Otherwise: `<version>-<stage>-<revision>`.
 */
export const formatBuild = ({
  version,
  stage,
  revision,
  versionOverride,
}: FormatBuildParams): string => {
  if (versionOverride !== undefined) {
    return versionOverride;
  }

  return [version, formatRevision(stage, revision)].filter(Boolean).join('-');
};
