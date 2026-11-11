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
 * - Any override defined (empty strings are valid): `<version><revision>` concatenated with no
 *   separator, where the part that is not overridden uses its built-in value.
 */
export const formatBuild = ({
  version,
  stage,
  revision,
  versionOverride,
  revisionOverride,
}: FormatBuildParams): string => {
  const versionPart = versionOverride ?? version;
  const revisionPart = revisionOverride ?? formatRevision(stage, revision);

  if (versionOverride !== undefined || revisionOverride !== undefined) {
    return `${versionPart}${revisionPart}`;
  }

  return [versionPart, revisionPart].filter(Boolean).join('-');
};
