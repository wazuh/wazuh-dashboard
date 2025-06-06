#!/usr/bin/env node

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

const fs = require('fs');
const { format: formatUrl } = require('url');
const { exitCode, start, ssl } = JSON.parse(process.argv[2]);
const { createServer } = ssl ? require('https') : require('http');
const { OPENSEARCH_KEY_PATH, OPENSEARCH_CERT_PATH } = require('@osd/dev-utils');

(function main() {
  process.exitCode = exitCode;

  if (!start) {
    return;
  }

  let serverUrl;
  const server = createServer(
    {
      // Note: the integration uses the OPENSEARCH_P12_PATH, but that keystore contains
      // the same key/cert as OPENSEARCH_KEY_PATH and OPENSEARCH_CERT_PATH
      key: ssl ? fs.readFileSync(OPENSEARCH_KEY_PATH, 'utf8') : undefined,
      cert: ssl ? fs.readFileSync(OPENSEARCH_CERT_PATH, 'utf8') : undefined,
    },
    (req, res) => {
      const url = new URL(req.url, serverUrl);
      const send = (code, body) => {
        res.writeHead(code, { 'content-type': 'application/json' });
        res.end(JSON.stringify(body));
      };

      if (url.pathname === '/_xpack') {
        return send(400, {
          error: {
            reason: 'foo bar',
          },
        });
      }

      return send(404, {
        error: {
          reason: 'not found',
        },
      });
    }
  );

  // setup server auto close after 3 seconds of silence
  let serverCloseTimer;
  const delayServerClose = () => {
    clearTimeout(serverCloseTimer);
    serverCloseTimer = setTimeout(() => server.close(), 3000);
  };
  server.on('request', delayServerClose);
  server.on('listening', delayServerClose);

  server.listen(0, '127.0.0.1', function () {
    const { port, address: hostname } = server.address();
    serverUrl = new URL(
      formatUrl({
        protocol: 'http:',
        port,
        hostname,
      })
    );

    console.log(
      `[o.e.h.AbstractHttpServerTransport] [computer] publish_address {127.0.0.1:${port}}, bound_addresses {[::1]:${port}}, {127.0.0.1:${port}}`
    );

    console.log('started');
  });
})();
