## [v5.0.0]

### Added

| Issue                                                                                        | Comment                                                                                     |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| [wazuh-dashboard-plugins#7532](https://github.com/wazuh/wazuh-dashboard-plugins/issues/7532) | Added the health check service and app                                                      |
| [#985](https://github.com/wazuh/wazuh-dashboard/issues/985)                                  | Added manager host configuration for the default configuration file                         |
| [#1052](https://github.com/wazuh/wazuh-dashboard/issues/1052)                                | Set v9 theme as default                                                                     |
| [wazuh-dashboard-plugins#8550](https://github.com/wazuh/wazuh-dashboard-plugins/issues/8550) | Added version, revision, and stage to the Wazuh build metadata                              |
| [#1434](https://github.com/wazuh/wazuh-dashboard/issues/1434)                                | Made the Discover CSV download row limit configurable via the `reports.csv.maxRows` setting |
| [#1480](https://github.com/wazuh/wazuh-dashboard/issues/1480)                                | Added automatic generation and storage of the AI assistant encryption key on first install  |

### Changed

| Issue                                                                                        | Comment                                                                                          |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| [#798](https://github.com/wazuh/wazuh-dashboard/issues/798)                                  | Changed the location of the wazuh-dashboard service to match with the other Wazuh components     |
| [#985](https://github.com/wazuh/wazuh-dashboard/issues/985)                                  | Changed the default value of `metaFields` and `timepicker:timeDefaults` settings                 |
| [wazuh-dashboard-plugins#8473](https://github.com/wazuh/wazuh-dashboard-plugins/issues/8473) | Excluded Wazuh dashboards and visualizations listing                                             |
| [#1329](https://github.com/wazuh/wazuh-dashboard/issues/1329)                                | Changed log level of the cross compatibility service on start                                    |
| [wazuh-dashboard-plugins#8979](https://github.com/wazuh/wazuh-dashboard-plugins/issues/8979) | Changed the sidecar flyout to displace open flyouts instead of covering them                     |
| [wazuh-dashboard-plugins#8989](https://github.com/wazuh/wazuh-dashboard-plugins/issues/8989) | Changed the sidecar resizable button emphasis styles to trigger on `:active` instead of `:focus` |

### Removed

| Issue                                                         | Comment                                                                                                                                                 |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [#699](https://github.com/wazuh/wazuh-dashboard/issues/699)   | Removed creation of /usr/lib/.build-id/\* links to prevent conflicts when installing Wazuh Dashboard alongside OpenSearch Dashboards on the same system |
| [#1381](https://github.com/wazuh/wazuh-dashboard/issues/1381) | Removed the Anomaly Detection plugin from the default Wazuh dashboard package                                                                           |

### Fixed

| Issue                                                         | Comment                                                                                      |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| [#1277](https://github.com/wazuh/wazuh-dashboard/issues/1277) | Fixed health check padding styles                                                            |
| [#1399](https://github.com/wazuh/wazuh-dashboard/issues/1399) | Prevent infinite remount loop when navigating from an app before its bundle finishes loading |

## Prior versions

- [v4.14.7](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.7/CHANGELOG.md)
- [v4.14.6](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.6/CHANGELOG.md)
- [v4.14.5](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.5/CHANGELOG.md)
- [v4.14.4](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.4/CHANGELOG.md)
- [v4.14.3](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.3/CHANGELOG.md)
- [v4.14.2](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.2/CHANGELOG.md)
- [v4.14.1](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.1/CHANGELOG.md)
- [v4.14.0](https://github.com/wazuh/wazuh-dashboard/blob/v4.14.0/CHANGELOG.md)
- [v4.13.1](https://github.com/wazuh/wazuh-dashboard/blob/v4.13.1/CHANGELOG.md)
- [v4.13.0](https://github.com/wazuh/wazuh-dashboard/blob/v4.13.0/CHANGELOG.md)
