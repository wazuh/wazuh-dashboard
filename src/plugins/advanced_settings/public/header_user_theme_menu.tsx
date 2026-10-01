/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { ChangeEvent, SyntheticEvent, useState } from 'react';
import { i18n } from '@osd/i18n';
import { FormattedMessage } from '@osd/i18n/react';
import {
  EuiSmallButton,
  EuiFlexGroup,
  EuiFlexItem,
  EuiCompressedFormRow,
  EuiHeaderSectionItemButton,
  EuiIcon,
  EuiLink,
  EuiPopover,
  EuiPopoverTitle,
  EuiCompressedSelect,
  EuiToolTip,
  EuiButtonIcon,
} from '@elastic/eui';
import { CoreStart } from 'opensearch-dashboards/public';
import { themeVersionLabelMap, themeVersionValueMap } from '@osd/ui-shared-deps/theme_config';
import { useOpenSearchDashboards, useUiSetting$ } from '../../opensearch_dashboards_react/public';

export const HeaderUserThemeMenu = () => {
  const {
    services: { uiSettings },
  } = useOpenSearchDashboards<CoreStart>();
  const themeVersionOptions = Object.keys(themeVersionLabelMap).map((v) => ({
    value: v,
    text: themeVersionLabelMap[v],
  }));
  const colorModeOptions = [
    {
      value: 'light',
      text: i18n.translate('advancedSettings.headerGlobalNav.colorMode.light', {
        defaultMessage: 'Light mode',
      }),
    },
    {
      value: 'dark',
      text: i18n.translate('advancedSettings.headerGlobalNav.colorMode.dark', {
        defaultMessage: 'Dark mode',
      }),
    },
    {
      value: 'automatic',
      text: i18n.translate('advancedSettings.headerGlobalNav.colorMode.automatic', {
        defaultMessage: 'Use browser settings',
      }),
    },
  ];
  const defaultThemeVersion = uiSettings.getDefault('theme:version');
  const defaultIsDarkMode = uiSettings.getDefault('theme:darkMode');
  const isUsingBrowserColorScheme =
    (window.localStorage.getItem('useBrowserColorScheme') && window.matchMedia) || false;
  const [isDarkMode, setIsDarkMode] = useUiSetting$<boolean>('theme:darkMode');
  const [themeVersion, setThemeVersion] = useUiSetting$<string>('theme:version');
  const [isPopoverOpen, setIsPopoverOpen] = useState(false);

  const [selectedThemeVersion, setSelectedThemeVersion] = useState(
    themeVersionOptions.find((t) => t.value === themeVersionValueMap[themeVersion])?.value ||
      themeVersionValueMap[defaultThemeVersion]
  );
  const [selectedColorMode, setSelectedColorMode] = useState(
    isUsingBrowserColorScheme
      ? colorModeOptions[2].value
      : isDarkMode
      ? colorModeOptions[1].value
      : colorModeOptions[0].value
  );
  const useLegacyAppearance = !uiSettings.get('home:useNewHomePage');

  const togglePopover = () => {
    setIsPopoverOpen(!isPopoverOpen);
  };

  const handleThemeVersionChange = (e: ChangeEvent<HTMLSelectElement>) => {
    setSelectedThemeVersion(e.target.value);
  };

  const handleColorModeChange = (e: ChangeEvent<HTMLSelectElement>) => {
    setSelectedColorMode(e.target.value);
  };

  const applyAppearanceSettings = async (e: SyntheticEvent) => {
    const pendingActions = [
      setThemeVersion(
        themeVersionOptions.find((t) => selectedThemeVersion === t.value)?.value ?? ''
      ),
    ];

    if (selectedColorMode === 'automatic') {
      const systemPrefersDarkMode = window.matchMedia('(prefers-color-scheme: dark)').matches;
      window.localStorage.setItem('useBrowserColorScheme', 'true');

      if (systemPrefersDarkMode !== isDarkMode) {
        pendingActions.push(setIsDarkMode(systemPrefersDarkMode));
      }
    } else if ((selectedColorMode === 'dark') !== isDarkMode) {
      pendingActions.push(setIsDarkMode(selectedColorMode === 'dark'));
      window.localStorage.removeItem('useBrowserColorScheme');
    } else {
      window.localStorage.removeItem('useBrowserColorScheme');
    }
    // TODO: only set changed
    await Promise.all(pendingActions);
    window.location.reload();
  };

  const closePopover = () => {
    setIsPopoverOpen(false);
  };

  const innerButton = useLegacyAppearance ? (
    <EuiHeaderSectionItemButton
      aria-expanded="false"
      aria-haspopup="true"
      aria-label={i18n.translate('advancedSettings.headerGlobalNav.themeMenuButtonAriaLabel', {
        defaultMessage: 'Appearance menu',
      })}
      onClick={togglePopover}
    >
      <EuiIcon type="color" size="m" />
    </EuiHeaderSectionItemButton>
  ) : (
    <EuiButtonIcon
      iconType="color"
      color="primary"
      size="xs"
      aria-expanded="false"
      aria-haspopup="true"
      aria-label={i18n.translate('advancedSettings.headerGlobalNav.themeMenuButtonAriaLabel', {
        defaultMessage: 'Appearance menu',
      })}
      onClick={togglePopover}
    />
  );

  const button = (
    <EuiToolTip
      content={i18n.translate('advancedSettings.headerGlobalNav.themeMenuButtonTitle', {
        defaultMessage: 'Appearance',
      })}
      delay="long"
      position="bottom"
    >
      {innerButton}
    </EuiToolTip>
  );

  const defaultColorModeLabel =
    colorModeOptions.find((t) => {
      const defaultValue = defaultIsDarkMode ? 'dark' : 'light';
      return defaultValue === t.value;
    })?.text ?? '';

  // TODO: fix focus behavior
  const appearanceContent = (
    <div style={{ maxWidth: 300 }}>
      <EuiCompressedFormRow
        label={i18n.translate('advancedSettings.headerGlobalNav.themeVersionLabel', {
          defaultMessage: 'Theme version',
        })}
        helpText={i18n.translate('advancedSettings.field.defaultValueText', {
          defaultMessage: 'Default: {value}',
          values: { value: defaultThemeVersion },
        })}
      >
        <EuiCompressedSelect
          options={themeVersionOptions}
          value={selectedThemeVersion}
          onChange={handleThemeVersionChange}
        />
      </EuiCompressedFormRow>
      <EuiCompressedFormRow
        label={i18n.translate('advancedSettings.headerGlobalNav.screenModeLabel', {
          defaultMessage: 'Screen mode',
        })}
        helpText={i18n.translate('advancedSettings.field.defaultValueText', {
          defaultMessage: 'Default: {value}',
          values: { value: defaultColorModeLabel },
        })}
      >
        <EuiCompressedSelect
          options={colorModeOptions}
          value={selectedColorMode}
          onChange={handleColorModeChange}
        />
      </EuiCompressedFormRow>
      <EuiFlexGroup>
        <EuiFlexItem>
          <EuiCompressedFormRow hasEmptyLabelSpace>
            <EuiLink
              target="_blank"
              href="https://forum.opensearch.org/t/feedback-on-dark-mode-experience/15725"
            >
              {i18n.translate('advancedSettings.headerGlobalNav.themeFeedbackLink', {
                defaultMessage: 'Theme feedback',
              })}
            </EuiLink>
          </EuiCompressedFormRow>
        </EuiFlexItem>
        <EuiFlexItem grow={false}>
          <EuiCompressedFormRow hasEmptyLabelSpace>
            {/* TODO: disable submit until changes */}
            <EuiSmallButton onClick={applyAppearanceSettings} type="submit">
              {i18n.translate('advancedSettings.headerGlobalNav.applyButtonLabel', {
                defaultMessage: 'Apply',
              })}
            </EuiSmallButton>
          </EuiCompressedFormRow>
        </EuiFlexItem>
      </EuiFlexGroup>
    </div>
  );

  return (
    <EuiPopover
      id="headerUserThemeContextMenu"
      button={button}
      isOpen={isPopoverOpen}
      closePopover={closePopover}
      anchorPosition={useLegacyAppearance ? 'downLeft' : 'rightDown'}
      panelPaddingSize="s"
    >
      <EuiPopoverTitle>
        <h2>
          <FormattedMessage
            id="advancedSettings.headerGlobalNav.appearanceMenuTitle"
            defaultMessage="Appearance"
          />
        </h2>
      </EuiPopoverTitle>
      {appearanceContent}
    </EuiPopover>
  );
};
