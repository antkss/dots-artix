USER=$1
if [ -z $USER ]; then
	echo "NULL user"
	exit
fi
echo "USER: $USER"
. func.sh

SU=
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
antkss() {
	$SU pacman -S usb_modeswitch mkinitcpio linux-own intel-ucode firmware-own
	$SU bash fstab.sh
	$SU bash dev.sh
	$SU ln -sr /boot/initramfs-own.img /boot/initrd -f
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
install_initial() {
	echo "setting up initialize packages ..."
	$SU pacman -S yay neovim --noconfirm
}
setup_group() {
	$SU usermod -aG video $USER
	$SU usermod -aG audio $USER
}
setup_source || exit
install_initial || exit
bash ./package.sh || exit
install_browser || exit
install_service || exit
install_network || exit
setup_utils || exit
choice "do you want to install antkss packages ?" "antkss || exit"
setup_clock
