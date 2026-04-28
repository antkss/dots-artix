#!/bin/sh
if [ -z $(which appimagetool) ];then
	yay -S appimagetool-bin
fi
mkdir -p appimage;
cd appimage;
if [ ! -f ./venv ]; then
	python3.13 -m venv venv
fi
source venv/bin/activate
pip3 install pillow materialyoucolor pyinstaller
cp ../generate_colors_material.py .
pyinstaller generate_colors_material.py 
cp -r ../assets/* dist/generate_colors_material
appimagetool dist/generate_colors_material
mv color_generator-x86_64.AppImage ../generate_colors_material
