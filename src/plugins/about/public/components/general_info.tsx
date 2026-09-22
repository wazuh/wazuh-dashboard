/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React from 'react';
import {
  EuiButtonIcon,
  EuiFlexGroup,
  EuiFlexItem,
  EuiPanel,
  EuiSpacer,
  EuiText,
  EuiTitle,
} from '@elastic/eui';
import type { HelpMenuLinkItem } from 'opensearch-dashboards/public';

const Section = ({ title, content }: { title: string; content: React.ReactNode }) => (
  <EuiFlexItem>
    <EuiPanel paddingSize="m">
      <EuiTitle size="m">
        <h2>{title}</h2>
      </EuiTitle>
      <EuiSpacer size="l" />
      {content}
    </EuiPanel>
  </EuiFlexItem>
);

export const AboutGeneralInfo = ({
  pluginAppName,
  communityLinks,
  darkMode,
}: {
  pluginAppName: string;
  communityLinks: HelpMenuLinkItem[];
  darkMode: boolean;
}) => {
  return (
    <EuiFlexGroup gutterSize="l" direction="row" responsive>
      <Section
        title={`Welcome to the ${pluginAppName}`}
        content={
          <EuiText size="m">
            <p>
              Dashboard provides management and monitoring capabilities, giving users control over
              the infrastructure. You can monitor your agents status and configuration, query and
              visualize your alert data and monitor manager rules and configuration.
            </p>
          </EuiText>
        }
      />
      {communityLinks.length > 0 && (
        <Section
          title="Community"
          content={
            <div>
              <EuiText size="m">
                <p>
                  Enjoy your experience and please don&apos;t hesitate to give us your feedback.
                </p>
              </EuiText>
              <EuiSpacer size="l" />
              <EuiFlexGroup alignItems="center" justifyContent="center" responsive={false}>
                {communityLinks.map((communityLink, index) => (
                  <EuiFlexItem grow={false} key={`aboutCommunityLink${index}`}>
                    <EuiButtonIcon
                      aria-label={communityLink.label}
                      iconType={
                        (darkMode && communityLink.darkModeIcon) || communityLink.icon || 'link'
                      }
                      iconSize="xxl"
                      href={communityLink.link}
                      target="_blank"
                    >
                      {communityLink.label}
                    </EuiButtonIcon>
                  </EuiFlexItem>
                ))}
              </EuiFlexGroup>
            </div>
          }
        />
      )}
    </EuiFlexGroup>
  );
};
