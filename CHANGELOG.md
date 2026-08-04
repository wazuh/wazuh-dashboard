## [v5.0.0]

### Added

| Issue                                                                                                                                                                                                                                                                                                                                                             | Comment                                                                                     |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
|                                                                                                                                                                                                                                                                                                                                                                   | Support for Wazuh 5.0.0                                                                     |
| [#811](https://github.com/wazuh/wazuh-dashboard/pull/811) [#866](https://github.com/wazuh/wazuh-dashboard/pull/866) [#961](https://github.com/wazuh/wazuh-dashboard/pull/961) [#1031](https://github.com/wazuh/wazuh-dashboard/pull/1031) [#1179](https://github.com/wazuh/wazuh-dashboard/pull/1179) [#1366](https://github.com/wazuh/wazuh-dashboard/pull/1366) | Health check service                                                                        |
| [#870](https://github.com/wazuh/wazuh-dashboard/pull/870) [#946](https://github.com/wazuh/wazuh-dashboard/pull/946) [#1366](https://github.com/wazuh/wazuh-dashboard/pull/1366) [#1379](https://github.com/wazuh/wazuh-dashboard/pull/1379)                                                                                                                       | Added Health Check app                                                                      |
| [#998](https://github.com/wazuh/wazuh-dashboard/pull/998)                                                                                                                                                                                                                                                                                                         | Added manager host configuration for the default configuration file                         |
| [#1092](https://github.com/wazuh/wazuh-dashboard/pull/1092)                                                                                                                                                                                                                                                                                                       | Set v9 theme as default                                                                     |
| [#1327](https://github.com/wazuh/wazuh-dashboard/pull/1327) [#1421](https://github.com/wazuh/wazuh-dashboard/pull/1421)                                                                                                                                                                                                                                           | Added version, revision, and stage to the Wazuh build metadata                              |
| [#1434](https://github.com/wazuh/wazuh-dashboard/issues/1434)                                                                                                                                                                                                                                                                                                     | Made the Discover CSV download row limit configurable via the `reports.csv.maxRows` setting |
| [#1480](https://github.com/wazuh/wazuh-dashboard/issues/1480)                                                                                                                                                                                                                                                                                                     | Added automatic generation and storage of the AI assistant encryption key on first install  |

### Fixed

| Issue                                                       | Comment                                                                                      |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| [#1276](https://github.com/wazuh/wazuh-dashboard/pull/1276) | Fixed health check padding styles                                                            |
| [#1285](https://github.com/wazuh/wazuh-dashboard/pull/1285) | Sanitized redirect path to prevent open redirect                                             |
| [#1400](https://github.com/wazuh/wazuh-dashboard/pull/1400) | Prevent infinite remount loop when navigating from an app before its bundle finishes loading |

### Removed

| Issue                                                       | Comment                                                                                                                                                 |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
|                                                             | Removed creation of /usr/lib/.build-id/\* links to prevent conflicts when installing Wazuh Dashboard alongside OpenSearch Dashboards on the same system |
| [#1382](https://github.com/wazuh/wazuh-dashboard/pull/1382) | Removed the Anomaly Detection plugin from the default Wazuh dashboard package                                                                           |

### Changed

| Issue                                                                                                                   | Comment                                                                                                            |
| ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| [#805](https://github.com/wazuh/wazuh-dashboard/issues/805)                                                             | Changed the location of the wazuh-dashboard service to match with the other Wazuh components                       |
| [#998](https://github.com/wazuh/wazuh-dashboard/pull/998)                                                               | Changed the default value of `metaFields` and `timepicker:timeDefaults` settings                                   |
| [#1278](https://github.com/wazuh/wazuh-dashboard/pull/1278) [#1279](https://github.com/wazuh/wazuh-dashboard/pull/1279) | Excluded Wazuh dashboards and visualizations listing                                                               |
| [#1330](https://github.com/wazuh/wazuh-dashboard/pull/1330)                                                             | Changed log level of the cross compatibility service on start                                                      |
| [#1328](https://github.com/wazuh/wazuh-dashboard/pull/1328) [#1365](https://github.com/wazuh/wazuh-dashboard/pull/1365) | Changed pre install scripts to block Wazuh dashboard installation if there's an existing installation prior to 5.x |

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
