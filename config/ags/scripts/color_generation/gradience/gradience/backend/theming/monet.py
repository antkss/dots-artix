# monet.py
#
# Change the look of Adwaita, with ease
# Copyright (C) 2022 Gradience Team
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

import os

from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM
from PIL import Image
from material_color_utilities_python.utils.theme_utils import themeFromImage

from gradience.backend.logger import Logger

logging = Logger()


class Monet:
    def __init__(self):
        self.palette = None

    def generate_from_image(self, image_path: str) -> dict:
        if image_path.endswith(".svg"):
            drawing = svg2rlg(image_path)
            runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
            if runtime_dir:
                image_path = os.path.join(
                    runtime_dir, "gradience_bg.png"
                )
                if drawing:
                    renderPM.drawToFile(drawing, image_path, fmt="PNG")

        if image_path.endswith(".xml"):
            # TODO: Use custom exception in future
            raise ValueError("XML files are unsupported by Gradience's Monet implementation")

        try:
            monet_img = Image.open(image_path)
        except Exception as e:
            logging.error("An error occurred while generating a Monet palette.", exc=e)
            raise
        else:
            basewidth = 64
            wpercent = basewidth / float(monet_img.size[0])
            hsize = int((float(monet_img.size[1]) * float(wpercent)))
            monet_img = monet_img.resize(
                (basewidth, hsize), Image.Resampling.LANCZOS
            )

            self.palette = themeFromImage(monet_img)

        return self.palette
