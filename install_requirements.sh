#!/usr/bin/env bash
set -euo pipefail
sudo systemctl stop firewalld.service
sudo systemctl disable firewalld.service
sudo yum install nginx -y
sudo systemctl enable nginx.service
sudo setsebool -P httpd_can_network_connect on

$HASH = "$6$t8QcbDFaIcWF279g$OeBOvqFs8WRsFvkRAy6jj/mnV1JgGkQegriejvEzR.02JvBpiqEs8esEHl7qXtKiLt.R.qWAE68u4Y3TJ9qOd."
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash -p "$HASH" "$USER_NAME"
  sudo usermod -aG gis gis
else
  sudo usermod -p "$HASH" "$USER_NAME"
  sudo usermod -aG gis gis
fi

