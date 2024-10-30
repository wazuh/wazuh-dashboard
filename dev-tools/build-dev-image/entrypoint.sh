#!/bin/bash
base_path_plugins="/home/node/kbn/plugins"
plugins=$(ls $base_path_plugins)
for plugin in $plugins; do
  if [ ! -d "$base_path_plugins/$plugin/node_modules" ]; then
    cd $base_path_plugins/$plugin
    echo "Installing dependencies for $plugin"
    yarn install
  fi
done

tail -f /dev/null
