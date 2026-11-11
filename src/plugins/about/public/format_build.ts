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
  /** `opensearchDashboards.branding.applicationRevision`, when defined. */
  revisionOverride?: string;
}

/**
 * Builds the build label shown in the About page.
 *
 * - Nothing overridden: `<version>-<stage>-<revision>`.
 * - Any override defined (empty strings are valid): only the defined settings are used, concatenated
 *   with no separator as `<applicationVersion><applicationRevision>`. The built-in values are not
 *   used, so a setting that is not defined contributes an empty string.
 */
export const formatBuild = ({
  version,
  stage,
  revision,
  versionOverride,
  revisionOverride,
}: FormatBuildParams): string => {
  if (versionOverride !== undefined || revisionOverride !== undefined) {
    return `${versionOverride ?? ''}${revisionOverride ?? ''}`;
  }

  return [version, formatRevision(stage, revision)].filter(Boolean).join('-');
};
