#!/bin/bash

LANG=en_us_8859_1

# fail on errors, undefined variables, and errors in pipes
set -eu
set -o pipefail

USER_ID=$(id -u)
if [ "$USER_ID" -ne 0 ]; then
	echo "must run with sudo !"
	exit 1
fi

###############################################################################
# STEP 1
###############################################################################
if [ -e /home/pi/DO_SLIMMING ]; then
	echo "Slimming down current image, step 1..."

	apt-get -y update
	# apt-get -y dist-upgrade

  rm -f /home/pi/DO_SLIMMING
	touch /home/pi/DO_SLIMMING_STEP2
	# reboot
	# exit 0
fi

###############################################################################
# STEP 2
###############################################################################
if [ -e /home/pi/DO_SLIMMING_STEP2 ]; then
	echo "Slimming down current image, step 2..."

# keep 'triggerhappy', 'alsa-utils' for raspi-config
# keep 'unzip' for factory-reset
	xargs apt-get -y purge <<"EOF"
aptitude aptitude-common apt-listchanges apt-utils bash-completion blends-tasks build-essential
bzip2 cifs-utils console-setup console-setup-linux cpp debconf-i18n dmidecode dosfstools
dpkg-dev ed gcc gcc-4.6-base gcc-4.7-base gcc-4.8-base gcc-4.9-base gcc-5-base gcc-6 gdb
geoip-database gettext-base groff-base hardlink htop info install-info iptables iputils-ping
isc-dhcp-client isc-dhcp-common kbd keyboard-configuration less libc-l10n libglib2.0-data
liblocale-gettext-perl libtext-charwidth-perl libtext-iconv-perl libtext-wrapi18n-perl locales
logrotate luajit make manpages manpages-dev mime-support mountall ncdu netcat-openbsd
netcat-traditional net-tools nfs-common perl plymouth python rpcbind rsync rsyslog samba-common
sgml-base shared-mime-info strace tasksel tasksel-data tcpd traceroute 
usb-modeswitch usb-modeswitch-data usbutils v4l-utils vim-common vim-tiny wget xauth
xdg-user-dirs xxd xz-utils zlib1g-dev scratch2 minecraft-pi wolfram-engine sonic-pi 
dillo libreoffice libreoffice-avmedia-backend-gstreamer libreoffice-base libreoffice-base-core 
libreoffice-base-drivers libreoffice-calc libreoffice-common libreoffice-core libreoffice-draw 
libreoffice-gtk libreoffice-gtk2 libreoffice-impress libreoffice-java-common libreoffice-math 
libreoffice-pi libreoffice-report-builder-bin libreoffice-sdbc-hsqldb libreoffice-style-galaxy 
libreoffice-systray libreoffice-writer squeak-vm squeak-plugins-scratch geany avahi-daemon cron ssh
EOF

	apt-get -y autoremove --purge
	apt-get -y clean

	echo "remove documentation..."
	find /usr/share/doc -depth -type f ! -name copyright | xargs -r rm -f
	find /usr/share/doc -empty | xargs rmdir
	rm -rf /usr/share/man/* /usr/share/groff/* /usr/share/info/*
	rm -rf /usr/share/lintian/* /usr/share/linda/* /var/cache/man/*

	echo "remove locales..."
	rm -rf /usr/share/locale/*

	echo "remove log files..."
	rm -f /var/log/{auth,boot,bootstrap,daemon,kern}.log
	rm -f /var/log/{debug,dmesg,messages,syslog}

	echo "empty motd..."
	:> /etc/motd

	rm -f /home/pi/DO_SLIMMING_STEP2
	rm -f /etc/rc.local
	mv /etc/rc.local.origin /etc/rc.local
	shutdown -h now
	sleep 5
	exit 0
fi