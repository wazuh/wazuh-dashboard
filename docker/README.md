# Frontend development environments

Install [Docker Desktop][0] as per its instructions, available for Windows, Mac 
and Linux (Ubuntu, Debian & Fedora).
This ensures that the development experience between Linux, Mac and Windows is as
similar as possible.

> IMPORTANT: be methodic during the installation of Docker Desktop, and proceed
step by step as described in their documentation. Make sure that your system
meets the system requirements before installing Docker Desktop, and read any 
post-installation note, specially on Linux: [Differences between 
Docker Desktop for Linux and Docker Engine](https://docs.docker.com/desktop/install/linux-install/#differences-between-docker-desktop-for-linux-and-docker-engine)

## Pre-requisites

 1. Assign resources to [Docker Desktop][0]. The requirements for the 
 environments are:
    - 8 GB of RAM (minimum)
    - 4 cores

    The more resources the better ☺

2. Have the [wazuh-dashboard](https://github.com/wazuh/wazuh-dashboard) repository and the [wazuh-security-dashboards-plugin](https://github.com/wazuh/wazuh-security-dashboards-plugin) repository cloned to the same level
 
3. Set up user permissions

    The Docker volumes will be created by the internal Docker user, making them
    read-only. To prevent this, a new group named `docker-desktop` and GUID 100999 
    needs to be created, then added to your user and the source code folder:

    ```bash
    sudo groupadd -g 100999 docker-desktop
    sudo useradd -u 100999 -g 100999 -M docker-desktop
    sudo chown -R docker-desktop:docker-desktop $WZD_HOME
    sudo usermod -aG docker-desktop $USER
    ```

## Understanding Docker contexts

Before we begin starting Docker containers, we need to understand the 
differences between Docker Engine and Docker Desktop, more precisely, that the 
use different contexts.

Carefully read these two sections of the Docker documentation:

- [Differences between Docker Desktop for Linux and Docker Engine](https://docs.docker.com/desktop/install/linux-install/#differences-between-docker-desktop-for-linux-and-docker-engine)
- [Switch between Docker Desktop and Docker Engine](https://docs.docker.com/desktop/install/linux-install/#context)

Docker Desktop will change to its context automatically at start, so be sure 
that any existing Docker container using the default context is **stopped** 
before starting Docker Desktop and any of the environments in this folder.

## Starting up the environments

Use the sh script to up the environment. 

Example:

```bash
./dev.sh 2.5.0 up
```

Once the containers are up, connect a shell to the development container, run yarn osd bootstrap to install the project dependencies. Then run yarn start to start the application.



[0]: <https://docs.docker.com/get-docker/> "Docker Desktop"
