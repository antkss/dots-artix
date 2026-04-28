#!/usr/bin/env bash

if [ "$1" == "--noswitch" ]; then
    imgpath=$(awww query | head -1 | awk -F 'image: ' '{print $2}')
    # imgpath=$(ags run-js 'wallpaper.get(0)')
else
    # Select and set image (hyprland)
	cd "$HOME/.images"
	imgpath=$(yad --width 1000 --height 600 --file --title='Choose wallpaper' --add-preview --large-preview &)
	if file --mime-type "$imgpath" | grep -q "image/gif" || file --mime-type "$imgpath" | grep -q "video"; then
		mv $imgpath $HOME/.cache/target
		cd $HOME/.cache
		ffmpeg -y -i target -filter_complex "[v:0]crop=iw:ih" -frames:v 1 -f image2 output%03d_awww.png
		mv $HOME/.cache/target $imgpath  
		if file --mime-type "$imgpath" | grep -q "image/gif"; then
		  notify-send "applying gif ..."
		  gifpath=$imgpath
		fi
		imgpath="$HOME/.cache/output001_awww.png"
		screensizey=$(xrandr --current | grep '*' | uniq | awk '{print $1}' | cut -d 'x' -f2 | head -1)
	fi

	if [ "$imgpath" == '' ]; then
		echo 'Aborted'
	exit 0
	fi
	if [ -v gifpath ]; then
	  awww img $gifpath
	  notify-send "waiting for gif to finish..."
	else
		# awww img "$imgpath" 
	  awww img "$imgpath" --transition-step 100 --transition-fps 120 \
			  --transition-type grow --transition-angle 30 --transition-duration 1 \
			  --transition-pos 0.854,0.977 
	fi
fi

&>/dev/null
GENERATE_SCRIPT="$HOME"/.config/ags/scripts/color_generation/generate_colors_material
if [ ! -f $GENERATE_SCRIPT ]; then
	GENERATE_SCRIPT="$HOME"/.config/ags/scripts/color_generation/generate_colors_material.py
fi
# Generate colors for ags n stuff
$GENERATE_SCRIPT --path ${imgpath} --scheme vibrant --apply --mode light --ags
# killall mbar; ~/.config/ags/mbar
