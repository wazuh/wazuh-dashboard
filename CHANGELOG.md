# Change Log

## [v5.0.0]

### Added

- Support for Wazuh 5.0.0
- Health check service [#811](https://github.com/wazuh/wazuh-dashboard/pull/811) [#866](https://github.com/wazuh/wazuh-dashboard/pull/866) [#961](https://github.com/wazuh/wazuh-dashboard/pull/961) [#1031](https://github.com/wazuh/wazuh-dashboard/pull/1031) [#1179](https://github.com/wazuh/wazuh-dashboard/pull/1179) [#1366](https://github.com/wazuh/wazuh-dashboard/pull/1366)
- Added Health Check app [#870](https://github.com/wazuh/wazuh-dashboard/pull/870) [#946](https://github.com/wazuh/wazuh-dashboard/pull/946) [#1366](https://github.com/wazuh/wazuh-dashboard/pull/1366) [#1379](https://github.com/wazuh/wazuh-dashboard/pull/1379)
- Added manager host configuration for the default configuration file [#998](https://github.com/wazuh/wazuh-dashboard/pull/998)
- Set v9 theme as default [#1092](https://github.com/wazuh/wazuh-dashboard/pull/1092)

### Fixed

- Fixed health check padding styles [#1276](https://github.com/wazuh/wazuh-dashboard/pull/1276)
- Sanitized redirect path to prevent open redirect [#1285](https://github.com/wazuh/wazuh-dashboard/pull/1285)

### Removed

- Removed creation of /usr/lib/.build-id/\* links to prevent conflicts when installing Wazuh Dashboard alongside OpenSearch Dashboards on the same system
- Removed the Anomaly Detection plugin from the default Wazuh dashboard package [#1382](https://github.com/wazuh/wazuh-dashboard/pull/1382)

### Changed

- Changed the location of the wazuh-dashboard service to match with the other Wazuh components [#805](https://github.com/wazuh/wazuh-dashboard/issues/805)
- Changed the default value of `metaFields` and `timepicker:timeDefaults` settings [#998](https://github.com/wazuh/wazuh-dashboard/pull/998)
- Excluded Wazuh dashboards and visualizations listing [#1278](https://github.com/wazuh/wazuh-dashboard/pull/1278) [#1279](https://github.com/wazuh/wazuh-dashboard/pull/1279)
- Changed log level of the cross compatibility service on start [#1330](https://github.com/wazuh/wazuh-dashboard/pull/1330)
- Changed pre install scripts to block Wazuh dashboard installation if there's an existing installation prior to 5.x [#1328](https://github.com/wazuh/wazuh-dashboard/pull/1328) [#1365](https://github.com/wazuh/wazuh-dashboard/pull/1365)

## Prior versions

- [v4.14.6](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.6/CHANGELOG.md)
- [v4.14.5](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.5/CHANGELOG.md)
- [v4.14.4](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.4/CHANGELOG.md)
- [v4.14.3](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.3/CHANGELOG.md)
- [v4.14.2](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.2/CHANGELOG.md)
- [v4.14.1](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.1/CHANGELOG.md)
- [v4.14.0](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.0/CHANGELOG.md)
- [v4.13.1](https://github.com/wazuh/wazuh-dashboard/blob/v4.13.1/CHANGELOG.md)
- [v4.13.0](https://github.com/wazuh/wazuh-dashboard/blob/v4.13.0/CHANGELOG.md)
