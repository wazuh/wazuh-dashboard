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

import { readFileSync } from 'fs';
import { resolve } from 'path';

import * as prettier from 'prettier';

import { REPO_ROOT } from '@osd/utils';
import { createFailError, ToolingLog } from '@osd/dev-utils';

import { File } from '../file';

export async function lintFiles(log: ToolingLog, files: File[], { fix }: { fix?: boolean } = {}) {
  const unformatted: string[] = [];

  for (const file of files) {
    const relativePath = file.getRelativePath();
    const absolutePath = resolve(REPO_ROOT, relativePath);
    const source = readFileSync(absolutePath, 'utf8');
    const options = await prettier.resolveConfig(absolutePath);
    const isFormatted = prettier.check(source, { ...options, filepath: absolutePath });

    if (!isFormatted) {
      unformatted.push(relativePath);
    }
  }

  if (unformatted.length > 0) {
    log.error(
      `[prettier] The following files are not formatted:\n${unformatted
        .map((f) => `  - ${f}`)
        .join('\n')}\n\nRun 'npx prettier --write <file>' to fix.`
    );
    throw createFailError('[prettier] Formatting errors found. Run prettier --write to fix.');
  }

  log.success('[prettier] %d file(s) checked, all formatted correctly', files.length);
}
