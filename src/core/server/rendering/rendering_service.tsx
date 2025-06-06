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
import { renderToStaticMarkup } from 'react-dom/server';
import { first, take } from 'rxjs/operators';
import { i18n, i18nLoader } from '@osd/i18n';
import { Agent as HttpsAgent } from 'https';

import Axios from 'axios';

import { UiPlugins } from '../plugins';
import { CoreContext } from '../core_context';
import { Template } from './views';
import {
  IRenderOptions,
  RenderingSetupDeps,
  InternalRenderingServiceSetup,
  RenderingMetadata,
  BrandingValidation,
  BrandingAssignment,
} from './types';
import { OpenSearchDashboardsConfigType } from '../opensearch_dashboards_config';
import { HttpConfigType } from '../http/http_config';
import { SslConfig } from '../http/ssl_config';
import { LoggerFactory } from '../logging';

const DEFAULT_TITLE = 'OpenSearch Dashboards';

/** @internal */
export class RenderingService {
  constructor(private readonly coreContext: CoreContext) {
    this.logger = this.coreContext.logger;
  }
  private logger: LoggerFactory;
  private httpsAgent?: HttpsAgent;

  public async setup({
    http,
    status,
    uiPlugins,
    dynamicConfig,
  }: RenderingSetupDeps): Promise<InternalRenderingServiceSetup> {
    const [opensearchDashboardsConfig, serverConfig] = await Promise.all([
      this.coreContext.configService
        .atPath<OpenSearchDashboardsConfigType>('opensearchDashboards')
        .pipe(first())
        .toPromise(),
      this.coreContext.configService.atPath<HttpConfigType>('server').pipe(first()).toPromise(),
    ]);

    this.setupHttpAgent(serverConfig as HttpConfigType);

    return {
      render: async (
        request,
        uiSettings,
        { includeUserSettings = true, vars }: IRenderOptions = {}
      ) => {
        const env = {
          mode: this.coreContext.env.mode,
          packageInfo: this.coreContext.env.packageInfo,
        };
        const basePath = http.basePath.get(request);
        const uiPublicUrl = `${basePath}/ui`;
        const serverBasePath = http.basePath.serverBasePath;
        const settings = {
          defaults: uiSettings.getRegistered(),
          user: includeUserSettings ? await uiSettings.getUserProvided() : {},
        };

        const brandingAssignment = await this.assignBrandingConfig(
          opensearchDashboardsConfig as OpenSearchDashboardsConfigType
        );

        let locale = i18n.getLocale();
        const localeOverride = (request.query as any)?.locale?.trim?.();
        if (localeOverride) {
          const normalizedLocale = i18n.normalizeLocale(localeOverride);
          if (i18nLoader.isRegisteredLocale(normalizedLocale)) {
            locale = normalizedLocale;
          }
        }

        const dynamicConfigStartServices = await dynamicConfig.getStartService();

        const metadata: RenderingMetadata = {
          strictCsp: http.csp.strict,
          uiPublicUrl,
          bootstrapScriptUrl: `${basePath}/bootstrap.js`,
          startupScriptUrl: `${basePath}/startup.js`,
          i18n: i18n.translate,
          locale,
          injectedMetadata: {
            version: env.packageInfo.version,
            buildNumber: env.packageInfo.buildNum,
            branch: env.packageInfo.branch,
            wazuhVersion: env.packageInfo.wazuhVersion,
            basePath,
            serverBasePath,
            env,
            anonymousStatusPage: status.isStatusPageAnonymous(),
            i18n: {
              translationsUrl: `${basePath}/translations/${locale}.json`,
            },
            csp: { warnLegacyBrowsers: http.csp.warnLegacyBrowsers },
            vars: vars ?? {},
            uiPlugins: await Promise.all(
              [...uiPlugins.public].map(async ([id, plugin]) => ({
                id,
                plugin,
                // TODO Scope the client so that only exposedToBrowser configs are exposed
                config: this.coreContext.dynamicConfigService.hasDefaultConfigs({ name: id })
                  ? await dynamicConfigStartServices.getClient().getConfig(
                      { name: id },
                      {
                        asyncLocalStorageContext: dynamicConfigStartServices.getAsyncLocalStore()!,
                      }
                    )
                  : await this.getUiConfig(uiPlugins, id),
              }))
            ),
            legacyMetadata: {
              uiSettings: settings,
            },
            branding: {
              assetFolderUrl: `${uiPublicUrl}/default_branding`,
              logo: {
                defaultUrl: brandingAssignment.logoDefault,
                darkModeUrl: brandingAssignment.logoDarkmode,
              },
              mark: {
                defaultUrl: brandingAssignment.markDefault,
                darkModeUrl: brandingAssignment.markDarkmode,
              },
              loadingLogo: {
                defaultUrl: brandingAssignment.loadingLogoDefault,
                darkModeUrl: brandingAssignment.loadingLogoDarkmode,
              },
              faviconUrl: brandingAssignment.favicon,
              applicationTitle: brandingAssignment.applicationTitle,
              useExpandedHeader: brandingAssignment.useExpandedHeader,
            },
            survey: opensearchDashboardsConfig.survey.url,
          },
        };

        return `<!DOCTYPE html>${renderToStaticMarkup(<Template metadata={metadata} />)}`;
      },
    };
  }

  public async stop() {}

  /**
   * Setups HTTP Agent if SSL is enabled to pass SSL config
   * values to Axios to make requests in while validating
   * resources.
   *
   * @param {Readonly<HttpConfigType>} httpConfig
   */
  private setupHttpAgent(httpConfig: Readonly<HttpConfigType>) {
    if (!httpConfig.ssl?.enabled) return;
    try {
      const sslConfig = new SslConfig(httpConfig.ssl);
      this.httpsAgent = new HttpsAgent({
        ca: sslConfig.certificateAuthorities,
        cert: sslConfig.certificate,
        key: sslConfig.key,
        passphrase: sslConfig.keyPassphrase,
        rejectUnauthorized: false,
      });
    } catch (e) {
      this.logger.get('branding').error('HTTP agent failed to setup for SSL.');
    }
  }

  /**
   * Assign values for branding related configurations based on branding validation
   * by calling checkBrandingValid(). If URL is valid, pass in
   * the actual URL; if not, pass in undefined.
   *
   * @param {Readonly<OpenSearchDashboardsConfigType>} opensearchDashboardsConfig
   * @returns {BrandingAssignment} valid URLs or undefined assigned for each branding configs
   */
  private assignBrandingConfig = async (
    opensearchDashboardsConfig: Readonly<OpenSearchDashboardsConfigType>
  ): Promise<BrandingAssignment> => {
    const brandingValidation: BrandingValidation = await this.checkBrandingValid(
      opensearchDashboardsConfig
    );
    const branding = opensearchDashboardsConfig.branding;

    // assign default mode URL based on the brandingValidation function result
    const logoDefault = brandingValidation.isLogoDefaultValid
      ? branding.logo.defaultUrl
      : undefined;

    const markDefault = brandingValidation.isMarkDefaultValid
      ? branding.mark.defaultUrl
      : undefined;

    const loadingLogoDefault = brandingValidation.isLoadingLogoDefaultValid
      ? branding.loadingLogo.defaultUrl
      : undefined;

    // assign dark mode URLs based on brandingValidation function result
    const logoDarkmode = brandingValidation.isLogoDarkmodeValid
      ? branding.logo.darkModeUrl
      : undefined;

    const markDarkmode = brandingValidation.isMarkDarkmodeValid
      ? branding.mark.darkModeUrl
      : undefined;

    const loadingLogoDarkmode = brandingValidation.isLoadingLogoDarkmodeValid
      ? branding.loadingLogo.darkModeUrl
      : undefined;

    // assign favicon based on brandingValidation function result
    const favicon = brandingValidation.isFaviconValid ? branding.faviconUrl : undefined;

    // assign application title based on brandingValidation function result
    const applicationTitle = brandingValidation.isTitleValid
      ? branding.applicationTitle
      : DEFAULT_TITLE;

    // use expanded menu by default unless explicitly set to false
    const { useExpandedHeader = true } = branding;

    const brandingAssignment: BrandingAssignment = {
      logoDefault,
      logoDarkmode,
      markDefault,
      markDarkmode,
      loadingLogoDefault,
      loadingLogoDarkmode,
      favicon,
      applicationTitle,
      useExpandedHeader,
    };

    return brandingAssignment;
  };

  /**
   * Assign boolean values for branding related configurations to indicate if
   * user inputs valid or invalid URLs by calling isUrlValid() function. Also
   * check if title is valid by calling isTitleValid() function.
   *
   * @param {Readonly<OpenSearchDashboardsConfigType>} opensearchDashboardsConfig
   * @returns {BrandingValidation} indicate valid/invalid URL for each branding config
   */
  private checkBrandingValid = async (
    opensearchDashboardsConfig: Readonly<OpenSearchDashboardsConfigType>
  ): Promise<BrandingValidation> => {
    const branding = opensearchDashboardsConfig.branding;
    const isLogoDefaultValid = await this.isUrlValid(branding.logo.defaultUrl, 'logo default');

    const isLogoDarkmodeValid = await this.isUrlValid(branding.logo.darkModeUrl, 'logo darkMode');

    const isMarkDefaultValid = await this.isUrlValid(branding.mark.defaultUrl, 'mark default');

    const isMarkDarkmodeValid = await this.isUrlValid(branding.mark.darkModeUrl, 'mark darkMode');

    const isLoadingLogoDefaultValid = await this.isUrlValid(
      branding.loadingLogo.defaultUrl,
      'loadingLogo default'
    );

    const isLoadingLogoDarkmodeValid = await this.isUrlValid(
      branding.loadingLogo.darkModeUrl,
      'loadingLogo darkMode'
    );

    const isFaviconValid = await this.isUrlValid(branding.faviconUrl, 'favicon');

    const isTitleValid = this.isTitleValid(branding.applicationTitle, 'applicationTitle');

    const brandingValidation: BrandingValidation = {
      isLogoDefaultValid,
      isLogoDarkmodeValid,
      isMarkDefaultValid,
      isMarkDarkmodeValid,
      isLoadingLogoDefaultValid,
      isLoadingLogoDarkmodeValid,
      isFaviconValid,
      isTitleValid,
    };

    return brandingValidation;
  };

  private async getUiConfig(uiPlugins: UiPlugins, pluginId: string) {
    const browserConfig = uiPlugins.browserConfigs.get(pluginId);

    return ((await browserConfig?.pipe(take(1)).toPromise()) ?? {}) as Record<string, any>;
  }

  /**
   * Validation function for URLs. Use Axios to call URL and check validity.
   * Also needs to be ended with png, svg, gif, PNG, SVG and GIF.
   *
   * @param {string} url
   * @param {string} configName
   * @returns {boolean} indicate if the URL is valid/invalid
   */
  public isUrlValid = async (url: string, configName?: string): Promise<boolean> => {
    if (url === '/') {
      return false;
    }
    if (url.match(/\.(png|svg|gif|PNG|SVG|GIF)$/) === null) {
      this.logger.get('branding').error(`${configName} config is invalid. Using default branding.`);
      return false;
    }
    if (url.startsWith('/')) {
      return true;
    }
    return await Axios.get(url, {
      httpsAgent: this.httpsAgent,
      adapter: 'http',
      maxRedirects: 0,
    })
      .then(() => {
        return true;
      })
      .catch(() => {
        this.logger
          .get('branding')
          .error(`${configName} URL was not found or invalid. Using default branding.`);
        return false;
      });
  };

  /**
   * Validation function for applicationTitle config.
   * Title length needs to be between 1 to 36 letters.
   *
   * @param {string} title
   * @param {string} configName
   * @returns {boolean} indicate if user input title is valid/invalid
   */
  public isTitleValid = (title: string, configName?: string): boolean => {
    if (!title) {
      return false;
    }
    if (title.length > 36) {
      this.logger
        .get('branding')
        .error(
          `${configName} config is not found or invalid. Title length should be between 1 to 36 characters. Using default title.`
        );
      return false;
    }
    return true;
  };
}
