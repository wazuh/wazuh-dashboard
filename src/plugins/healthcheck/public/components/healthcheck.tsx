/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useEffect, useMemo, useState } from 'react';
import { i18n } from '@osd/i18n';
import { FormattedMessage, I18nProvider } from '@osd/i18n/react';
import { EuiFlexGroup, EuiFlexItem, EuiText, EuiHorizontalRule, EuiBadge } from '@elastic/eui';
import useObservable from 'react-use/lib/useObservable';
import { groupBy } from 'lodash';
import { TaskInfo } from 'src/core/common/healthcheck';
import { useMount } from 'react-use';
import { ButtonExportHealthCheck } from './export_checks';
import { HealthIcon } from './health_icon';
import { ButtonFilterChecksCheck, CheckFilters, checkFilters } from './filter_checks';
import { TASK } from '../constants';
import { getHealthCheck } from '../dashboards_services';
import { getCore } from '../dashboards_services';
import { getHealthFromStatus } from './services/health';
import { GroupByResult } from './group_by_result';

export const HealthCheck = () => {
  const core = getCore();

  useMount(() => {
    core.chrome.setBreadcrumbs([
      {
        text: i18n.translate('healthcheck.breadcrumbs.title', {
          defaultMessage: 'Health check',
        }),
      },
    ]);

    core.chrome.docTitle.change(
      i18n.translate('healthcheck.pageTitle', { defaultMessage: 'Health check' })
    );
  });

  const { status$, client, getConfig } = getHealthCheck();
  const {
    internal: { fetch },
  } = client;
  const { status, checks } = useObservable(status$, status$.getValue());
  const [filterChecks, setFilterChecks] = useState<Array<{ id: CheckFilters }>>([]);

  useEffect(() => {
    getConfig().then(() => {
      fetch().catch();
    });
  }, [fetch, getConfig]);

  const filterCheck = (check: TaskInfo, _index: number, _arr: TaskInfo[]) => {
    return filterChecks.length > 0 ? filterChecks.some(({ id }) => checkFilters[id](check)) : true;
  };

  const filteredChecks = checks.filter(filterCheck);
  const filteredChecksGroupByResult = groupBy(filteredChecks, 'result');

  const filteredChecksResultRed = filteredChecks.filter(
    (check) => check.result === TASK.RUN_RESULT.RED && check._meta?.isCritical
  );
  const filteredChecksResultYellow = filteredChecks.filter(
    (check) =>
      (check.result === TASK.RUN_RESULT.RED && !check._meta?.isCritical) ||
      check.result === TASK.RUN_RESULT.YELLOW
  );
  const filteredChecksResultGreen = filteredChecks.filter(
    (check) => check.result === TASK.RUN_RESULT.GREEN
  );

  const checksGroupByResult = useMemo(() => {
    return groupBy(checks, 'result');
  }, [checks]);

  const contextMenuPanel = (
    <div>
      <EuiFlexGroup
        gutterSize="xs"
        justifyContent="spaceBetween"
        alignItems="center"
        responsive={false}
      >
        <EuiFlexItem grow={false}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'right' }}>
            <EuiText>
              <h3>
                <FormattedMessage id="healthcheck.statusTitle" defaultMessage="Status is " />
                <EuiBadge color={getHealthFromStatus(status)}>{status}</EuiBadge>
              </h3>
            </EuiText>
            <div style={{ marginLeft: '4px' }}>
              {[TASK.RUN_RESULT.GREEN, TASK.RUN_RESULT.RED, TASK.RUN_RESULT.GRAY].map((result) => {
                const groupedByResult = checksGroupByResult[result]?.length;
                const filteredCheckByResult = filteredChecksGroupByResult?.[result]?.length ?? 0;
                if (groupedByResult) {
                  return (
                    <HealthIcon key={result} status={result}>
                      {filteredCheckByResult !== groupedByResult
                        ? `${filteredCheckByResult} (${groupedByResult})`
                        : groupedByResult}
                    </HealthIcon>
                  );
                }
                return null;
              })}
            </div>
          </div>
        </EuiFlexItem>
        <EuiFlexItem grow={false}>
          <EuiFlexGroup gutterSize="xs" responsive={false} alignItems="center">
            <EuiFlexItem grow={false}>
              <ButtonFilterChecksCheck filters={filterChecks} setFilters={setFilterChecks} />
            </EuiFlexItem>
            <EuiFlexItem grow={false}>
              <ButtonExportHealthCheck data={{ status, checks }} />
            </EuiFlexItem>
          </EuiFlexGroup>
        </EuiFlexItem>
      </EuiFlexGroup>
      <EuiHorizontalRule margin="xs" />
      <EuiFlexGroup direction="column" gutterSize="xs" responsive={false}>
        {filteredChecksResultGreen.length > 0 && (
          <EuiFlexItem>
            <GroupByResult result={TASK.RUN_RESULT.GREEN} checks={filteredChecksResultGreen} />
          </EuiFlexItem>
        )}
        {filteredChecksResultYellow.length > 0 && (
          <EuiFlexItem>
            <GroupByResult result={TASK.RUN_RESULT.YELLOW} checks={filteredChecksResultYellow} />
          </EuiFlexItem>
        )}
        {filteredChecksResultRed.length > 0 && (
          <EuiFlexItem>
            <GroupByResult result={TASK.RUN_RESULT.RED} checks={filteredChecksResultRed} />
          </EuiFlexItem>
        )}
      </EuiFlexGroup>
    </div>
  );

  return <I18nProvider>{contextMenuPanel}</I18nProvider>;
};
