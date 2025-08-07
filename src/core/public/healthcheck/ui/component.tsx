/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { FormattedMessage, I18nProvider } from '@osd/i18n/react';
import {
  EuiButtonEmpty,
  EuiContextMenuPanel,
  EuiHeaderSectionItemButton,
  EuiHealth,
  EuiFlexGroup,
  EuiPopover,
  EuiToolTip,
  EuiFlexItem,
  EuiText,
  EuiButtonIcon,
  EuiHorizontalRule,
} from '@elastic/eui';
import useObservable from 'react-use/lib/useObservable';
import { groupBy } from 'lodash';
import { interval } from 'rxjs';
import { useAsyncAction } from './hook/use_async_action';
import { ButtonExportHealthCheck } from './export_checks';
import { HealthIcon } from './health_icon';
import { getHealthFromStatus } from './services/health';
import { CheckDetails } from './check_details';
import { ButtonFilterChecksCheck, checkFilters } from './filter_checks';
import { TASK } from '../constants';

export const HealthCheckNavButton = (props) => {
  const [isPopoverOpen, setPopoverOpen] = useState<boolean>(false);
  const { status, checks } = useObservable(props.status$, props.status$.getValue());
  const runAction = useAsyncAction(() => props.run());
  const updateInterval = useRef();
  const [filterChecks, setFilterChecks] = useState([]);

  useEffect(() => {
    props.getConfig().then((config) => {
      props.fetch().catch();
      const intervalConfig = config?.interval;
      if (interval) {
        updateInterval.current = interval(intervalConfig).subscribe(() => props.fetch());
      }
    });

    return () => updateInterval?.current?.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const filterCheck = (check) => {
    return filterChecks.length > 0 ? filterChecks.some(({ id }) => checkFilters[id](check)) : true;
  };

  const filteredChecks = checks.filter(filterCheck);
  const filteredChecksGroupByResult = groupBy(filteredChecks, 'result');

  const checksGroupByResult = useMemo(() => {
    return groupBy(checks, 'result');
  }, [checks]);

  const runFailedAction = useAsyncAction(
    () => props.run(checksGroupByResult.fail.map(({ name }) => name)),
    [checksGroupByResult]
  );

  const isPlacedInLeftNav = props.coreStart.uiSettings.get('home:useNewHomePage');

  const overallStatusIndicator = (
    <EuiHealth
      color={getHealthFromStatus(status)}
      onClick={() => setPopoverOpen((prevState) => !prevState)}
    />
  );

  // ToDo: Add aria-label and tooltip when isPlacedInLeftNav is true
  const button = (
    <EuiToolTip
      content={
        <FormattedMessage
          id="core.healthcheck.status.tooltip"
          defaultMessage="Health check status: {status}"
          values={{
            status,
          }}
        />
      }
      position="bottom"
    >
      {overallStatusIndicator}
    </EuiToolTip>
  );
  const innerElement = isPlacedInLeftNav ? (
    <EuiButtonEmpty
      size="xs"
      flush="both"
      className="accountNavButton"
      aria-expanded={isPopoverOpen}
      aria-haspopup="true"
    >
      {button}
    </EuiButtonEmpty>
  ) : (
    button
  );

  const contextMenuPanel = (
    <div style={{ maxWidth: '400px' }}>
      <EuiFlexGroup
        gutterSize="xs"
        justifyContent="spaceBetween"
        alignItems="center"
        responsive={false}
      >
        <EuiFlexItem grow={false}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'right' }}>
            <HealthIcon status={status} />
            <EuiText>
              <h3>
                <FormattedMessage id="core.healthcheck.title" defaultMessage="Health check" />
              </h3>
            </EuiText>
            <div style={{ marginLeft: '4px' }}>
              {[TASK.RUN_RESULT.GREEN, TASK.RUN_RESULT.RED, TASK.RUN_RESULT.NULL].map((result) => {
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
            <EuiFlexItem grow={false}>
              <EuiToolTip
                content={
                  <FormattedMessage
                    id="core.healthcheck.run.only_failed"
                    defaultMessage="Run failed checks"
                  />
                }
                position="bottom"
              >
                <EuiButtonIcon
                  iconType="refresh"
                  onClick={() => runFailedAction.run()}
                  isDisabled={
                    !checksGroupByResult?.fail ||
                    checksGroupByResult?.fail?.length === 0 ||
                    runFailedAction.running
                  }
                  iconSize="l"
                  color="danger"
                  aria-label="Run failed checks"
                />
              </EuiToolTip>
            </EuiFlexItem>
            <EuiFlexItem grow={false}>
              <EuiToolTip
                content={
                  <FormattedMessage
                    id="core.healthcheck.run.enabled"
                    defaultMessage="Run enabled checks"
                  />
                }
                position="bottom"
              >
                <EuiButtonIcon
                  iconType="refresh"
                  onClick={runAction.run}
                  isDisabled={runAction.running}
                  iconSize="l"
                  aria-label="Run enabled checks"
                />
              </EuiToolTip>
            </EuiFlexItem>
          </EuiFlexGroup>
        </EuiFlexItem>
      </EuiFlexGroup>
      <EuiHorizontalRule margin="xs" />
      <EuiFlexGroup
        direction="column"
        gutterSize="xs"
        responsive={false}
        style={{ overflowY: 'scroll', maxHeight: '65vh', overflowX: 'hidden' }}
      >
        {filteredChecks.map((check) => (
          <EuiFlexItem key={check.name}>
            <div>
              <CheckDetails
                check={check}
                run={() => props.run([check.name])}
                formatDate={props.formatDate}
              />
            </div>
          </EuiFlexItem>
        ))}
      </EuiFlexGroup>
    </div>
  );

  return (
    <I18nProvider>
      <EuiHeaderSectionItemButton id="user-icon-btn" size="l">
        <EuiPopover
          data-test-subj="account-popover"
          id="actionsMenu"
          anchorPosition={isPlacedInLeftNav ? 'rightDown' : undefined}
          button={innerElement}
          isOpen={isPopoverOpen}
          closePopover={() => {
            setPopoverOpen(false);
          }}
          panelPaddingSize="s"
        >
          <EuiContextMenuPanel>{contextMenuPanel}</EuiContextMenuPanel>
        </EuiPopover>
      </EuiHeaderSectionItemButton>
    </I18nProvider>
  );
};
