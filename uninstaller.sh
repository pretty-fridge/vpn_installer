#!/bin/bash

sudo sh -c "$(wget -qO- https://github.com/v2rayA/v2rayA-installer/raw/main/uninstaller.sh)"
sleep 3
systemctl disable sub-convert.timer sub-http.service vpntester.timer
rm -f /etc/systemd/system/{sub-convert.service,sub-convert.timer,sub-http.service,vpntester.service,vpntester.timer}
rm -f /usr/local/bin/{vpntester,sub-convert,enable-sub-import}
rm -f /etc/home-vpn.env
systemctl daemon-reload
