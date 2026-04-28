# common.py
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
import subprocess

import unicodedata


def to_slug_case(non_slug) -> str:
    return unicodedata.normalize("NFKD", non_slug)

def run_command(command, *args, **kwargs):
    if isinstance(command, str): # run on the host
        command = [command]
    if os.environ.get('FLATPAK_ID'): # run in flatpak
        command = ['flatpak-spawn', '--host'] + command

    return subprocess.run(command, *args, **kwargs, check=True)
