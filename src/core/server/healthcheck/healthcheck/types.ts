/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { Duration } from 'moment';
import { WorkspaceStart } from 'opensearch-dashboards/server/workspace';
import { DynamicConfigServiceStart } from 'opensearch-dashboards/server/config';
import { CrossCompatibilityServiceStart } from 'opensearch-dashboards/server/cross_compatibility';
import { CoreUsageDataStart } from 'opensearch-dashboards/server/core_usage_data';
import { AuditTrailStart } from 'opensearch-dashboards/server/audit_trail';
import { UiSettingsServiceStart } from 'opensearch-dashboards/server/ui_settings';
import { MetricsServiceStart } from 'opensearch-dashboards/server/metrics';
import { HttpServiceStart } from 'opensearch-dashboards/server/http';
import { OpenSearchServiceStart } from 'opensearch-dashboards/server/opensearch';
import { CapabilitiesStart } from 'opensearch-dashboards/server';
import { SavedObjectsStartDeps } from 'opensearch-dashboards/server/saved_objects/saved_objects_service';
import { ITask, TaskDefinition } from '../task/types';

// Healcheck
export interface HealthCheckServiceSetup {
  register: (task: TaskDefinition) => void;
  get: (name: string) => ITask;
  getAll: () => ITask[];
}

export type HealthCheckServiceStart = HealthCheckServiceSetup;

export interface HealthCheckServiceStartDeps {
  capabilities: CapabilitiesStart;
  opensearch: OpenSearchServiceStart;
  http: HttpServiceStart;
  metrics: MetricsServiceStart;
  savedObjects: SavedObjectsStartDeps;
  uiSettings: UiSettingsServiceStart;
  auditTrail: AuditTrailStart;
  coreUsageData: CoreUsageDataStart;
  crossCompatibility: CrossCompatibilityServiceStart;
  dynamicConfig: DynamicConfigServiceStart;
  workspace: WorkspaceStart;
}

export interface HealthCheckConfigDefinition {
  enabled: boolean;
  checks_enabled: string | string[];
  retries_delay: Duration;
  max_retries: number;
  interval: Duration;
  server_not_ready_troubleshooting_link: string;
}

export type HealthCheckConfig = Omit<HealthCheckConfigDefinition, 'retries_delay' | 'interval'> & {
  retries_delay: number;
  interval: number;
};
