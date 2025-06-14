#!/bin/bash
SU=doas
HOME_DIR=$HOME
default=()
if [ "$(id -u)" -ne 0 ]; then
  echo "settings up $(id)"
else
    echo "Please run on the target user, not for root"
    exit 1
fi
choice(){
    local text=$1
    local cmd=$2
    local p 
    local ask=false 

    echo "$text"

    while true; do
        read -p "(y|n) => " p
        case "$p" in
            [yY]) 
                ask=true
                break 
                ;;
            [nN]) 
                ask=false
                break 
                ;;
            *) 
                echo "Invalid input. Please enter 'y' for yes or 'n' for no."
                ;;
        esac
    done

    if [[ "$ask" == true ]]; then
        $cmd
    fi
}

install_initial() {
	echo "setting up initialize packages ..."
	$SU pacman -S yay neovim --noconfirm
}
install_service() {
	echo "setting up service"
}
install_browser() {
	echo "setting up browser ..."
	$SU pacman -S firefox --noconfirm
}
install_network() {
	echo "setting up core ..."
	$SU pacman -S networkmanager-openrc networkmanager --noconfirm
	$SU rc-update add NetworkManager default
}
setup_utils() {
	echo "setting up utils ..."
	# chmod +s $(which brightnessctl reboot poweroff)
	CUSTOM_SCRIPT=/etc/init.d/randomdis
	BRIGHTNESSCTL=/etc/init.d/brightnessctl
	if [ ! -f $CUSTOM_SCRIPT ]; then
		$SU cp custom/randomdis $CUSTOM_SCRIPT
	fi
	if [ ! -f $BRIGHTNESSCTL ]; then
		$SU cp custom/brightnessctl $BRIGHTNESSCTL
	fi
	$SU rc-update add randomdis default
	$SU rc-update add brightnessctl default
	# some script use /usr/bin/bash
	if [ ! -f /usr/bin/bash ]; then 
		$SU ln -s /bin/bash /usr/bin/bash
	fi
}
setup_user() {
	echo "setting up user ..."
	INIT_DIR=$HOME_DIR/.config/rc/runlevels/sysinit
	$SU usermod -aG video $(whoami)
	$SU usermod -aG audio $(whoami)
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
antkss() {
	$SU pacman -S usb_modeswitch mkinitcpio linux-own intel-ucode firmware-own
	$SU bash fstab.sh
	$SU bash dev.sh
	$SU ln -sr /boot/initramfs-linux-6.6.93-0-own.img /boot/initrd -f
	$SU ln -sr /boot/vmlinuz-own /boot/vmlinuz -f
	# optional linux-firmware
}
setup_source() {
	$SU bash ./source.sh
}
setup_clock() {
	$SU ln -sf /usr/share/zoneinfo/Asia/Ho_Chi_Minh /etc/localtime
	$SU hwclock --systohc

}

echo "setting up alpine linux ..."
setup_source || exit
install_initial || exit
$SU bash ./package.sh || exit
install_browser || exit
install_service || exit
install_network || exit
setup_utils || exit
setup_user || exit
choice "do you want to install antkss packages ?" "antkss || exit"
choice "do you want to install aur packages ?" "bash aur.sh || exit"
setup_clock
echo "setup done ! please reboot your device"



