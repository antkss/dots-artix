#!/bin/bash
SU=doas
HOME_DIR=$HOME
if [ "$(id -u)" -ne 0 ]; then
  echo "settings up $(id)"
else
    echo "Please run on the target user, not for root"
    exit 1
fi
. func.sh


setup_user() {
	echo "setting up user ..."
	INIT_DIR=$HOME_DIR/.config/rc/runlevels/sysinit

	if [ ! -d  $INIT_DIR ]; then 
		mkdir -p $INIT_DIR
	fi
	rc-update --user add pipewire default
	rc-update --user add wireplumber default
	rc-update --user add dbus default
	if [ ! -d $HOME_DIR/.config ]; then
		mkdir $HOME_DIR/.config
	fi
	# setup config
	if [ ! -f $HOME_DIR/.config/config_lock ]; then
		cp -r config/* $HOME_DIR/.config
		touch $HOME_DIR/.config/config_lock
		echo "config copied !"
	else
		echo "lock exist, skipping config overwrite ..."
	fi
}



echo "setting up alpine linux ..."
$SU bash root.sh $(whoami) || exit
choice "do you want to install aur packages ?" "bash aur.sh || exit"
setup_user || exit
echo "setup done ! please reboot your device"



