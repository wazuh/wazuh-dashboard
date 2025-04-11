## Images

To setup the crendentials (**this only has to be done once**):

1. Login to Quay.io and navigate to User Settings.
2. Click on `CLI Password: Generate Encrypted Password`
3. In the new window that opens, click on `Docker Configuration` and follow the steps.

To build an image, use the docker build command like:

Use the `--build-arg` flag to specify the version of Node and the version of
the platform. The version of Node to use is defined in the `.nvmrc` file. Use
the Node version defined in that file for the target platform version, as the
version of Node might be increased between platfform's versions.

For example, to build the image for OpenSearch Dashboards `5.0.0`:

```bash
# Usage:
docker build \
  --build-arg NODE_VERSION=18.19.0 \
  --build-arg OPENSEARCH_DASHBOARD_VERSION=2.18.0.0 \
  --build-arg WAZUH_DASHBOARD_BRANCH=5.0.0 \
  --build-arg WAZUH_DASHBOARD_SECURITY_BRANCH=5.0.0 \
  --build-arg WAZUH_DASHBOARD_REPORTING_BRANCH=5.0.0 \
  --build-arg WAZUH_DASHBOARD_PLUGINS_BRANCH=5.0.0 \
  -t quay.io/wazuh/osd-dev:2.18.0 \
  -f wzd.dockerfile .
```

For arm architecture if you have amd architecture you need to add `--platform linux/arm64` and if you have arm for amd architecture you need to add `--platform linux/amd64`  

Push the image to Quay:

```bash
docker push quay.io/wazuh/image-name:version
```

If you're creating a new image, copy one of the ones already present
in the directory, and adapt it to the new version.