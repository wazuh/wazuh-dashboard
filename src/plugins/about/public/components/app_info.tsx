/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import { EuiCallOut, EuiFlexGroup, EuiFlexItem, EuiText, EuiTextColor } from '@elastic/eui';

export const AboutAppInfo = ({
  version,
  clusterUuid,
}: {
  version: string;
  clusterUuid?: string | null;
}) => {
  return (
    <EuiCallOut>
      <EuiFlexGroup
        direction="row"
        alignItems="flexStart"
        justifyContent="flexStart"
        gutterSize="l"
        responsive
      >
        <EuiFlexItem>
          <EuiText>
            App version: <b>{version}</b>
          </EuiText>
        </EuiFlexItem>
        <EuiFlexItem>
          <EuiText>
            Cluster UUID:{' '}
            <b>{clusterUuid ? clusterUuid : <EuiTextColor color="subdued">-</EuiTextColor>}</b>
          </EuiText>
        </EuiFlexItem>
      </EuiFlexGroup>
    </EuiCallOut>
  );
};
