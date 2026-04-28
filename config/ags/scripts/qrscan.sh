#!/bin/sh
sh ~/.config/ags/scripts/grimblast.sh --freeze save area /tmp/imageqr.png
if [ -f /tmp/imageqr.png ]; then
	wl-copy $(zbarimg /tmp/imageqr.png --raw)
	rm /tmp/imageqr.png
else
	wl-copy "qr scan cancelled !"
fi
