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

/* eslint-disable react/no-danger */

import React, { FunctionComponent } from 'react';

export const Styles: FunctionComponent = () => {
  return (
    <style
      dangerouslySetInnerHTML={{
        __html: `
          *, *:before, *:after {
            box-sizing: border-box;
          }

          html, body, div, span, svg {
            margin: 0;
            padding: 0;
            border: none;
            vertical-align: baseline;
          }

          body, html {
            width: 100%;
            height: 100%;
            margin: 0;
            display: block;
          }

          {/* used on loading page */}
          .osdWelcomeView {
            line-height: 1.5;
            height: 100%;
            display: -webkit-box;
            display: -webkit-flex;
            display: -ms-flexbox;
            display: flex;
            -webkit-box-flex: 1;
            -webkit-flex: 1 0 auto;
                -ms-flex: 1 0 auto;
                    flex: 1 0 auto;
            -webkit-box-orient: vertical;
            -webkit-box-direction: normal;
            -webkit-flex-direction: column;
                -ms-flex-direction: column;
                    flex-direction: column;
            -webkit-box-align: center;
            -webkit-align-items: center;
                -ms-flex-align: center;
                    align-items: center;
            -webkit-box-pack: center;
            -webkit-justify-content: center;
                -ms-flex-pack: center;
                    justify-content: center;
          }

          .legacyBrowserErrorLogo {
            height: 64px;
          }

          .osdWelcomeTitle {
            font-size: 20px;
            margin: 16px 0;
            animation: fadeIn 1s ease-in-out;
            animation-fill-mode: forwards;
            opacity: 0;
            animation-delay: 1.0s;
          }

          .osdWelcomeText {
            display: inline-block;
            font-size: 24px; /* Wazuh */
            font-family: sans-serif;
            line-height: 40px !important;
            height: 40px !important;
          }

          .osdLoaderWrap {
            text-align: center;
            line-height: 1;
            text-align: center;
            letter-spacing: -.005em;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
            font-kerning: normal;
            font-weight: 400;
          }

          .osdLoaderWrap svg {
            width: 384px;	 /* Wazuh */
            height: 112px; /* Wazuh */
            margin: auto;
            line-height: 1;
          }

          .osdLoader path {
            stroke: white;
          }

          .osdProgress {
            display: inline-block;
            position: relative;
            width: 256px;	/* Wazuh */
            height: 10px;
            overflow: hidden;
            line-height: 1;
          }

          .osdProgress:before {
            position: absolute;
            content: '';
            height: 10px; /* Wazuh */
            width: 100%;
            top: 0;
            bottom: 0;
            left: 0;
            transform: scaleX(0) translateX(0%);
            animation: osdProgress 1s cubic-bezier(.694, .0482, .335, 1) infinite;
          }

          .loadingLogoContainer {
            height: 100px; /* Wazuh */
            padding: 10px 10px 10px 10px;
          }

          .loadingLogo {
            height: 100%;
            max-width: 100%;
          }

          .darkOnly, .lightOnly {
            display: none;
          }

          @keyframes osdProgress {
            0% {
              transform: scaleX(1) translateX(-100%);
            }

            100% {
              transform: scaleX(1) translateX(100%);
            }
          }
        `,
      }}
    />
  );
};
