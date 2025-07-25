# Package building

This folder contains tools used to create `tar`, `rpm` and `deb` packages.

## Requirements

- A system with Docker.
- Internet connection (to download the docker images the first time).

## How to build packages

The script `build-packages.sh` is in charge of coordinating the different steps to build each type of packages.

### Pre-requisites

The script needs 4 different zip files, containing the following respectively:

- The base of Wazuh Dashboard, generated by running `yarn build --linux --skip-os-packages --release` or `yarn build --linux-arm --skip-os-packages --release` for arm packages
- The build of each plugin in `wazuh-dashboard-plugins` repo
- The build of the `wazuh-security-dashboards-plugin` repo
- The build of the `wazuh-dashboards-reporting ` repo

### Building packages

The script can build a `.tar.gz` (former base), and `rpm` and `deb` packages. This can be for x64 and arm architectures (it is not cross-architecture building. You need to run the script in a machine of the same architecture that you are building).

The inputs are the following:

- `-c`, `--commit-sha`: Set the commit sha of this build.
- `-a`, `--app`: URL or path to the zip that contains the `wazuh-dashboard-plugins` plugins build.
- `-b`, `--base`: URL or path to the zip that contains the `wazuh-dashboard build`.
- `-s`, `--security`: URL or path to the zip that contains the `wazuh-security-dashboards-plugin` build.
- `-rp`, `--reportPlugin`: URL or path to the zip that contains the `wazuh-dashboards-reporting` build.
- `-r`, `--revision`: [Optional] Set the revision of this build. By default, it is set to 1.
- `--all-platforms`: Build all platforms.
- `--deb`: Build deb.
- `--rpm`: Build rpm.
- `--tar`: Build tar.gz.
- `--production`:[Optional] The naming of the package will be ready for production. Otherwise, it will include the hash of the current commit.
- `--arm`: [Optional] Build for arm64 instead of x64.
- `--debug`: [Optional] Enables debug mode, which will show detailed information during the script run.
- `--silent`: [Optional] Enables silent mode, which will show the minimum possible information during the script run. `--debug` has priority over this.
- `--help`: Show the help message.

> [!IMPORTANT]
> In the inputs where a local path is available, use `file://<absolute_path>` to indicate it.

> [!WARNING]
> To build `arm` packages, you need to run the script in an arm machine, and use an arm build of the wazuh-dashboard base with `-b`

Example:

```bash
bash build-packages.sh \
    --app file:///home/user/packages/wazuh-package.zip \
    --base file:///home/user/packages/dashboard-package.zip \
    --security file:///home/user/packages/security-package.zip \
    --reportPlugin file:///home/user/packages/report-package.zip \
    --revision 2 --deb --silent
```