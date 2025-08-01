/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { schema, TypeOf } from '@osd/config-schema';
import { ConfigDeprecationProvider } from 'src/core/server';
import { ServiceConfigDescriptor } from '../../internal_types';

export type HealthCheckConfigType = TypeOf<typeof configSchema>;

/**
 * Validation schema for initialization service config.
 * @public
 */
const schemaChecksEnabled = schema.string();
export const configSchema = schema.object({
  enabled: schema.boolean({ defaultValue: true }),
  checks_enabled: schema.oneOf([schemaChecksEnabled, schema.arrayOf(schemaChecksEnabled)], {
    defaultValue: '.*',
  }),
  schedule_interval: schema.duration({
    defaultValue: 15 * 60 * 1000,
    validate: (value) => {
      const minValue = 5 * 60 * 1000;
      const maxValue = 24 * 60 * 60 * 1000;
      return value.asMilliseconds() < minValue || value.asMilliseconds() > maxValue
        ? 'Value is not valid. This should be between 5 minutes (5m) and 24 hours (24h)'
        : undefined;
    },
  }),
  retries_delay: schema.duration({
    defaultValue: 2.5 * 1000,
    validate: (value) => {
      const minValue = 0;
      const maxValue = 6 * 60 * 60 * 1000;
      return value.asMilliseconds() < minValue || value.asMilliseconds() > maxValue
        ? 'Value is not valid. This should be between 0 seconds (0s) and 6 hours (6h)'
        : undefined;
    },
  }),
  max_retries: schema.number({ defaultValue: 5 }),
});

const deprecations: ConfigDeprecationProvider = ({ renameFromRoot, renameFromRootWithoutMap }) => [
  (settings, fromPath, log) => {
    return settings;
  },
];

export const config: ServiceConfigDescriptor<HealthCheckConfigType> = {
  path: 'healthcheck',
  schema: configSchema,
  deprecations,
};
