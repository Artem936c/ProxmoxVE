#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://immich.app

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_uv

msg_info "Установка зависимостей"
msg_ok "Set up Postgresql Database"

APPLICATION="immich"

LD_LIBRARY_PATH=/usr/local/lib
export LD_RUN_PATH=/usr/local/lib
STAGING_DIR=/opt/staging
BASE_REPO="https://github.com/immich-app/base-images"
BASE_DIR=${STAGING_DIR}/base-images
SOURCE_DIR=${STAGING_DIR}/image-source

INSTALL_DIR="/opt/${APPLICATION}"
UPLOAD_DIR="${INSTALL_DIR}/upload"
SRC_DIR="${INSTALL_DIR}/source"
APP_DIR="${INSTALL_DIR}/app"
PLUGIN_DIR="${APP_DIR}/corePlugin"
ML_DIR="${APP_DIR}/machine-learning"
GEO_DIR="${INSTALL_DIR}/geodata"

msg_info "Installing GeoNames data"
cd "$GEO_DIR"
curl -fsSLZ -O "https://raw.githubusercontent.com/Artem936c/ProxmoxVE/main/admin1CodesASCII.txt" \
  -O "https://raw.githubusercontent.com/Artem936c/ProxmoxVE/main/admin2Codes.txt" \
  -O "https://download.geonames.org/export/dump/cities500.zip" \
  -O "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson"
unzip -q cities500.zip
date --iso-8601=seconds | tr -d "\n" >geodata-date.txt
rm cities500.zip
cd "$INSTALL_DIR"
ln -s "$GEO_DIR" "$APP_DIR"
msg_ok "Installed GeoNames data"

mkdir -p /var/log/immich
touch /var/log/immich/{web.log,ml.log}
msg_ok "Installed ${APPLICATION}"

msg_info "Modifying user, creating env file, scripts & services"
usermod -aG video,render immich

cat <<EOF >"${INSTALL_DIR}"/.env
TZ=$(cat /etc/timezone)
IMMICH_VERSION=release
NODE_ENV=production

DB_HOSTNAME=127.0.0.1
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}
DB_DATABASE_NAME=${DB_NAME}
DB_VECTOR_EXTENSION=vectorchord

REDIS_HOSTNAME=127.0.0.1
IMMICH_MACHINE_LEARNING_URL=http://127.0.0.1:3003
MACHINE_LEARNING_CACHE_FOLDER=${INSTALL_DIR}/cache
## - For OpenVINO only - uncomment below to increase
## - inference speed while reducing accuracy
## - Default is FP32
# MACHINE_LEARNING_OPENVINO_PRECISION=FP16

IMMICH_MEDIA_LOCATION=${UPLOAD_DIR}
EOF
cat <<EOF >"${ML_DIR}"/ml_start.sh
#!/usr/bin/env bash

cd ${ML_DIR}
. ${VIRTUAL_ENV}/bin/activate

set -a
. ${INSTALL_DIR}/.env
set +a

python3 -m immich_ml
EOF
cat <<EOF >"$APP_DIR"/bin/start.sh
#!/usr/bin/env bash

set -a
. ${INSTALL_DIR}/.env
set +a

/usr/bin/node ${APP_DIR}/dist/main.js "\$@"
EOF
chmod +x "$ML_DIR"/ml_start.sh "$APP_DIR"/bin/start.sh
cat <<EOF >/etc/systemd/system/"${APPLICATION}"-web.service
[Unit]
Description=${APPLICATION} Web Service
After=network.target
Requires=redis-server.service
Requires=postgresql.service
Requires=immich-ml.service

[Service]
Type=simple
User=immich
Group=immich
UMask=0077
WorkingDirectory=${APP_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/bin/node ${APP_DIR}/dist/main
Restart=on-failure
SyslogIdentifier=immich-web
StandardOutput=append:/var/log/immich/web.log
StandardError=append:/var/log/immich/web.log

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/"${APPLICATION}"-ml.service
[Unit]
Description=${APPLICATION} Machine-Learning
After=network.target

[Service]
Type=simple
UMask=0077
User=immich
Group=immich
WorkingDirectory=${APP_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=${ML_DIR}/ml_start.sh
Restart=on-failure
SyslogIdentifier=immich-machine-learning
StandardOutput=append:/var/log/immich/ml.log
StandardError=append:/var/log/immich/ml.log

[Install]
WantedBy=multi-user.target
EOF
chown -R immich:immich "$INSTALL_DIR" /var/log/immich
systemctl enable -q --now "$APPLICATION"-ml.service "$APPLICATION"-web.service
msg_ok "Modified user, created env file, scripts and services"

motd_ssh
customize
cleanup_lxc
