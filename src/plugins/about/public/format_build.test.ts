/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { formatBuild, formatRevision } from './format_build';

describe('formatRevision', () => {
  it('renders the stage followed by the revision separated by a hyphen', () => {
    expect(formatRevision('rc3', '11')).toBe('rc3-11');
  });

  it('renders only the stage when there is no revision', () => {
    expect(formatRevision('rc3', '')).toBe('rc3');
  });

  it('renders only the revision when there is no stage', () => {
    expect(formatRevision('', '11')).toBe('11');
  });

  it('renders an empty string when there is neither', () => {
    expect(formatRevision(undefined, undefined)).toBe('');
  });
});

describe('formatBuild', () => {
  const build = { version: '5.0.0', stage: 'rc3', revision: '11' };

  it('joins the version, the stage and the revision with hyphens when nothing is defined', () => {
    expect(formatBuild(build)).toBe('5.0.0-rc3-11');
  });

  it('renders only the version when there is no stage nor revision', () => {
    expect(formatBuild({ version: '5.0.0' })).toBe('5.0.0');
  });

  it('concatenates the custom version with the default revision with no separator', () => {
    expect(formatBuild({ ...build, versionOverride: 'v' })).toBe('vrc3-11');
  });

  it('concatenates the default version with the custom revision with no separator', () => {
    expect(formatBuild({ ...build, revisionOverride: '-custom' })).toBe('5.0.0-custom');
    expect(formatBuild({ ...build, revisionOverride: 'custom' })).toBe('5.0.0custom');
  });

  it('accepts an empty custom revision', () => {
    expect(formatBuild({ ...build, revisionOverride: '' })).toBe('5.0.0');
  });

  it('accepts an empty custom version', () => {
    expect(formatBuild({ ...build, versionOverride: '' })).toBe('rc3-11');
  });

  it('concatenates both custom values', () => {
    expect(formatBuild({ ...build, versionOverride: '6.0', revisionOverride: ' (beta)' })).toBe(
      '6.0 (beta)'
    );
    expect(formatBuild({ ...build, versionOverride: '', revisionOverride: '' })).toBe('');
  });
});
