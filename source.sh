#!/bin/bash
if [ "$(id -u)" -ne 0 ]; then
	echo "please run as root"
	exit
fi
sort_mirror() {
	pacman -S archlinux-mirrorlist pacman-contrib parallel --noconfirm
	echo "getting mirrorlist ..."
	curl https://gitea.artixlinux.org/packages/artix-mirrorlist/raw/branch/master/mirrorlist -o /tmp/mirrorlist
	echo "getting the fastest ..."
	./rankmirrors -v -n 5 -p /tmp/mirrorlist | tee /etc/pacman.d/mirrorlist
	rm /tmp/mirrorlist
}
. func.sh
choice "Do you want to sort the fastest artix mirror ?" sort_mirror


pacman-key --init
pacman-key --populate
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' --noconfirm
pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' --noconfirm
echo "setting up server ..."
repo="\[antk\]"
repo_="[antk]"
server="Server = https://antkss.github.io/packages"
if [ ! -n "$(cat /etc/pacman.conf | grep $repo )" ]; then 
	echo "applying :$repo_ ..."
	echo -ne "\n$repo_\nSigLevel = Optional TrustAll\n$server" >> /etc/pacman.conf
fi
repo="\[chaotic-aur\]"
repo_="[chaotic-aur]"
server="Include = /etc/pacman.d/chaotic-mirrorlist"
if [ ! -n "$(cat /etc/pacman.conf | grep $repo )" ]; then 
	echo "applying :$repo_ ..."
	echo -ne "\n$repo_\n$server" >> /etc/pacman.conf
fi
repo="\[omniverse\]"
repo_="[omniverse]"
server="Server = https://artix.sakamoto.pl/omniverse/\$arch\n"
server+="Server = https://eu-mirror.artixlinux.org/omniverse/\$arch\n"
server+="Server = https://omniverse.artixlinux.org/\$arch"
if [ ! -n "$(cat /etc/pacman.conf | grep $repo )" ]; then 
	echo "applying :$repo_ ..."
	echo -ne "\n$repo_\n$server" >> /etc/pacman.conf
fi
repo="\[extra\]"
repo_="[extra]"
server="Include = /etc/pacman.d/mirrorlist-arch"
if [ ! -n "$(cat /etc/pacman.conf | grep $repo )" ]; then 
	echo "applying :$repo_ ..."
	echo -ne "\n$repo_\n$server" >> /etc/pacman.conf
fi
repo="\[multilib\]"
repo_="[multilib]"
server="Include = /etc/pacman.d/mirrorlist-arch"
if [ ! -n "$(cat /etc/pacman.conf | grep $repo )" ]; then 
	echo "applying :$repo_ ..."
	echo -ne "\n$repo_\n$server" >> /etc/pacman.conf
fi
pacman -Sy
