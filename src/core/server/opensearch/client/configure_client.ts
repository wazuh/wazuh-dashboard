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

import { Buffer } from 'buffer';
import { stringify } from 'querystring';
import {
  Client,
  ClientOptions,
  Transport,
  RequestEvent,
  errors,
} from '@opensearch-project/opensearch';
import { RequestBody } from '@opensearch-project/opensearch/lib/Transport';

import { Logger } from '../../logging';
import { parseClientOptions, OpenSearchClientConfig } from './client_config';

export const configureClient = (
  config: OpenSearchClientConfig,
  {
    logger,
    scoped = false,
    withLongNumeralsSupport = false,
    customTransport,
  }: {
    logger: Logger;
    scoped?: boolean;
    withLongNumeralsSupport?: boolean;
    customTransport?: typeof Transport;
  }
): Client => {
  const clientOptions: ClientOptions = parseClientOptions(config, scoped);
  if (withLongNumeralsSupport) clientOptions.enableLongNumeralSupport = true;
  if (customTransport) clientOptions.Transport = customTransport;

  const client = new Client(clientOptions);
  addLogging(client, logger, config.logQueries);

  return client;
};

const addLogging = (client: Client, logger: Logger, logQueries: boolean) => {
  client.on('response', (error, event) => {
    if (error) {
      logger.error(formatResponseError(error, event));
    }
    if (event && logQueries) {
      const params = event.meta.request.params;

      // definition is wrong, `params.querystring` can be either a string or an object
      const querystring = convertQueryString(params.querystring);
      const url = `${params.path}${querystring ? `?${querystring}` : ''}`;
      const body = params.body ? `\n${ensureString(params.body)}` : '';
      logger.debug(`${event.statusCode}\n${params.method} ${url}${body}`, {
        tags: ['query'],
      });
    }
  });
};

const MAX_LOGGED_BODY_LENGTH = 500;

// error details for response errors provided by opensearch, defaults to error name/message
const formatResponseError = (error: Error, event: RequestEvent) => {
  const type = event.body?.error?.type;
  const reason = event.body?.error?.reason;
  if (type == null && reason == null && error instanceof errors.ResponseError) {
    return `[${error.name}]: ${describeBodylessResponseError(error, event)}`;
  }
  return `[${type ?? error.name}]: ${reason ?? error.message}`;
};

// Some responses (e.g. the security plugin rejecting a request) carry a plain-text body instead
// of an OpenSearch error object, so the status, request and body are the only hint to the cause.
const describeBodylessResponseError = (error: Error, event: RequestEvent) => {
  const params = event.meta?.request?.params;
  const request = [event.statusCode, params?.method, params?.path].filter(Boolean).join(' ');
  const body = typeof event.body === 'string' ? truncateBody(event.body) : '';
  const detail = body || error.message;
  return request ? `${request}: ${detail}` : detail;
};

const truncateBody = (body: string) => {
  const singleLine = body.replace(/\s+/g, ' ').trim();
  return singleLine.length > MAX_LOGGED_BODY_LENGTH
    ? `${singleLine.slice(0, MAX_LOGGED_BODY_LENGTH)}…`
    : singleLine;
};

const convertQueryString = (qs: string | Record<string, any> | undefined): string => {
  if (qs === undefined || typeof qs === 'string') {
    return qs ?? '';
  }
  return stringify(qs);
};

function ensureString(body: RequestBody): string {
  if (typeof body === 'string') return body;
  if (Buffer.isBuffer(body)) return '[buffer]';
  if ('readable' in body && body.readable && typeof body._read === 'function') return '[stream]';
  return JSON.stringify(body);
}
