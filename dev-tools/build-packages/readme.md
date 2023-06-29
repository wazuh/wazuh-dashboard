# Package building
This folder contains tools used to create `rpm` and `deb` packages. 

## Requirements
 - A system with Docker
 - Internet connection (to download the docker images the first time)

## Content
### Base
To generate packages, the scripts require a Wazuh Dashboard `.tar.gz`  file, containing the Wazuh App, the Wazuh Security plugin and other used plugins. 

The `generate_base.sh` script generates that `.tar.gz` using the following inputs: 
- `-a` | `--app`: the location of the zipped Wazuh App. It can be a URL or a PATH, with the format `file://<absolute_path>`
- `-b` | `--base`: the location of the Wazuh Dashboard `.tar.gz` without any plugin. It can be a URL or a PATH, with the format `file://<absolute_path>`, and can be generated with `yarn build --skip-os-packages --release` in the main Wazuh Dashboard repository. 
- `-s` | `--security`: the location of the zipped Wazuh Security Plugin. It can be a URL or a PATH, with the format `file://<absolute_path>`, and can be generated with `yarn build` in the main Wazuh Security Plugin repository.
- `-v` | `--version`: the Wazuh version of the package.
- `-r` | `--revision`: [Optional] Set the revision of the build. By default, it is set to 1.
- `-o` | `--output` [Optional] Set the destination path of package. By default, an output folder will be created in the same directory as the script.

An example command is: 
```
./generate_base.sh --app https://packages-dev.wazuh.com/pre-release/ui/dashboard/wazuh-4.4.0-1.zip -b file:///home/user/dashboard/wazuh-dashboard/target/opensearch-dashboards-2.4.1-linux-x64.tar.gz -s file:///home/user/dashboard/wazuh-security-dashboards-plugin/build/security-dashboards-2.4.1.0.zip -v 4.4.0
```

### Deb
The `launcher.sh` command generates a `.deb` package based on the previously generated `.tar.gz`. To do it, it uses a Docker instance. It takes the following inputs:
- `-v` | `--version`: the Wazuh version of the package.
- `-p` | `--package`: the location of the `.tar.gz` file. It can be a URL or a PATH, with the format `file://<absolute_path>`
- `-r` | `--revision`: [Optional] Set the revision of the build. By default, it is set to 1.
- `-o` | `--output` [Optional] Set the destination path of package. By default, an output folder will be created in the same directory as the script. 
- `--dont-build-docker`: [Optional] Locally built Docker image will be used instead of generating a new one.

An example command is:
```
./launcher.sh -v 4.4.0 -p file:///home/user/dashboard/wazuh-dashboard/dev-tools/build-packages/base/output/wazuh-dashboard-4.4.0-1-linux-x64.tar.gz
```

### Rpm
The `launcher.sh` command generates a `.rpm` package based on the previously generated `.tar.gz`. To do it, it uses a Docker instance. It takes the following inputs:
- `-v` | `--version`: the Wazuh version of the package.
- `-p` | `--package`: the location of the `.tar.gz` file. It can be a URL or a PATH, with the format `file://<absolute_path>`
- `-r` | `--revision`: [Optional] Set the revision of the build. By default, it is set to 1.
- `-o` | `--output` [Optional] Set the destination path of package. By default, an output folder will be created in the same directory as the script. 
- `--dont-build-docker`: [Optional] Locally built Docker image will be used instead of generating a new one.

An example command is:
```
./launcher.sh -v 4.4.0 -p file:///home/user/dashboard/wazuh-dashboard/dev-tools/build-packages/base/output/wazuh-dashboard-4.4.0-1-linux-x64.tar.gz
```
