#!/bin/bash

sudo sh -c "$(wget -qO- https://github.com/v2rayA/v2rayA-installer/raw/main/uninstaller.sh)"
sleep 3
rm /etc/systemd/system/{sub-convert.service,sub-convert.timer,sub-http.service,vpntester.service,vpntester.timer}
rm /usr/local/bin/{vpntester,sub-convert,enable-sub-import}
rm /etc/home-vpn.env
