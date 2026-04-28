#!/usr/bin/env python3

import argparse
import json
import os
import re
import signal
import sys
import types
import unicodedata
import warnings
from pathlib import Path
from pathlib import Path
from gi.repository import GLib, Gio
from gi.repository import GLib, Gio

from gradience.backend.css_parser import parse_css
from gradience.backend.globals import get_gtk_theme_dir, preset_repos, PRESETS_DIR
from gradience.backend.logger import Logger
from gradience.backend.models.preset import Preset
from gradience.backend.theming.preset_utils import PresetUtils
from gradience.backend.utils.common import to_slug_case
from gradience.backend.constants import BUILTIN_PRESET_SLUGS, ROOTDIR, SCRIPT_DIR
_DOWNLOADER = None
_FLATPAK = None


class CLIError(RuntimeError):
    pass


def get_downloader():
    global _DOWNLOADER

    if _DOWNLOADER is None:
        from gradience.backend.preset_downloader import PresetDownloader

        _DOWNLOADER = PresetDownloader

    return _DOWNLOADER


def get_flatpak_tools():
    global _FLATPAK

    if _FLATPAK is None:
        from gradience.backend.flatpak_overrides import (
            allow_file_access,
            create_gtk_user_override,
            disallow_file_access,
            list_file_access,
            remove_gtk_user_override,
        )

        _FLATPAK = types.SimpleNamespace(
            allow_file_access=allow_file_access,
            create_gtk_user_override=create_gtk_user_override,
            disallow_file_access=disallow_file_access,
            list_file_access=list_file_access,
            remove_gtk_user_override=remove_gtk_user_override,
        )

    return _FLATPAK



def get_plugin_manager():
    global _PLUGIN_MANAGER

    if _PLUGIN_MANAGER is None:
        from yapsy.PluginManager import PluginManager

        _PLUGIN_MANAGER = PluginManager

    return _PLUGIN_MANAGER


class SettingsStore:
    def __init__(self, app_id):
        self._gio = None
        self._app_id = app_id
        self._fallback_path = Path(
            os.environ.get(
                "XDG_CONFIG_HOME",
                os.path.join(os.environ["HOME"], ".config"),
            )
        ) / "gradience-cli" / "settings.json"
        self._fallback = {
            "enabled-plugins": [],
            "enabled-repos": {},
            "favourite": [],
            "global-flatpak-theming-gtk3": False,
            "global-flatpak-theming-gtk4": False,
            "repos": {},
            "user-flatpak-theming-gtk3": False,
            "user-flatpak-theming-gtk4": False,
        }

        try:
            schema_source = Gio.SettingsSchemaSource.get_default()
            schema = (
                schema_source.lookup(app_id, False)
                if schema_source is not None
                else None
            )
            if schema is not None:
                self._gio = Gio.Settings.new(app_id)
        except Exception:
            self._gio = None

        if self._gio is None and self._fallback_path.exists():
            self._fallback.update(
                json.loads(self._fallback_path.read_text(encoding="utf-8"))
            )

    def _save_fallback(self):
        self._fallback_path.parent.mkdir(parents=True, exist_ok=True)
        self._fallback_path.write_text(
            json.dumps(self._fallback, indent=2, sort_keys=True),
            encoding="utf-8",
        )

    def get_string_list(self, key):
        if self._gio is not None:
            return list(self._gio.get_value(key).unpack())
        return list(self._fallback.get(key, []))

    def set_string_list(self, key, values):
        values = list(values)
        if self._gio is not None:
            self._gio.set_value(key, GLib.Variant("as", values))
            return
        self._fallback[key] = values
        self._save_fallback()

    def get_mapping(self, key):
        if self._gio is not None:
            value = self._gio.get_value(key).unpack()
            return {
                name: raw.unpack() if hasattr(raw, "unpack") else raw
                for name, raw in value.items()
            }
        return dict(self._fallback.get(key, {}))

    def set_mapping(self, key, values):
        normalized = {str(name): str(url) for name, url in values.items()}
        if self._gio is not None:
            payload = {
                name: GLib.Variant("s", value)
                for name, value in normalized.items()
            }
            self._gio.set_value(key, GLib.Variant("a{sv}", payload))
            return
        self._fallback[key] = normalized
        self._save_fallback()

    def get_boolean(self, key):
        if self._gio is not None:
            return bool(self._gio.get_boolean(key))
        return bool(self._fallback.get(key, False))

    def set_boolean(self, key, value):
        value = bool(value)
        if self._gio is not None:
            self._gio.set_boolean(key, value)
            return
        self._fallback[key] = value
        self._save_fallback()


class GradienceCLI:
    def __init__(self, version, app_id):
        self.version = version
        self.app_id = app_id
        self.logging = Logger()
        self._settings = None
        self.parser = self._build_parser()

    @property
    def settings(self):
        if self._settings is None:
            self._settings = SettingsStore(self.app_id)
        return self._settings

    def _build_parser(self):
        parser = argparse.ArgumentParser(
            description="Gradience - Change the look of Adwaita, with ease"
        )
        parser.add_argument(
            "-V",
            "--version",
            action="version",
            version=f"Gradience, version {self.version}",
        )

        subparsers = parser.add_subparsers(dest="command")

        presets_parser = subparsers.add_parser("presets", help="list installed presets")
        presets_parser.add_argument(
            "-j",
            "--json",
            action="store_true",
            help="print presets in JSON format",
        )
        presets_parser.set_defaults(func=self.list_presets)

        builtins_parser = subparsers.add_parser(
            "builtins",
            help="list built-in presets",
        )
        builtins_parser.add_argument(
            "-j",
            "--json",
            action="store_true",
            help="print presets in JSON format",
        )
        builtins_parser.set_defaults(func=self.list_builtin_presets)

        favorites_parser = subparsers.add_parser(
            "favorites",
            help="list favorite presets",
        )
        favorites_parser.add_argument(
            "-a",
            "--add-preset",
            metavar="PRESET_NAME",
            help="add a preset to favorites",
        )
        favorites_parser.add_argument(
            "-r",
            "--remove-preset",
            metavar="PRESET_NAME",
            help="remove a preset from favorites",
        )
        favorites_parser.add_argument(
            "-j",
            "--json",
            action="store_true",
            help="print favorites in JSON format",
        )
        favorites_parser.set_defaults(func=self.favorite_presets)

        import_parser = subparsers.add_parser("import", help="import a preset")
        import_parser.add_argument(
            "-p",
            "--preset-path",
            required=True,
            help="absolute path to a preset file",
        )
        import_parser.set_defaults(func=self.import_preset)

        apply_parser = subparsers.add_parser("apply", help="apply a preset")
        apply_group = apply_parser.add_mutually_exclusive_group(required=True)
        apply_group.add_argument(
            "-n",
            "--preset-name",
            help="display name or builtin id for a preset",
        )
        apply_group.add_argument(
            "-p",
            "--preset-path",
            help="absolute path to a preset file",
        )
        apply_parser.add_argument(
            "--gtk",
            choices=["gtk4", "gtk3", "both"],
            default="gtk4",
            help="types of applications you want to theme (default: gtk4)",
        )
        apply_parser.add_argument(
            "--no-plugins",
            action="store_true",
            help="skip applying enabled plugins after theming",
        )
        apply_parser.set_defaults(func=self.apply_preset)

        current_parser = subparsers.add_parser(
            "current",
            help="inspect or save the currently applied preset",
        )
        current_parser.add_argument(
            "--gtk",
            choices=["gtk4", "gtk3"],
            default="gtk4",
            help="theme target to inspect (default: gtk4)",
        )
        current_parser.add_argument(
            "-j",
            "--json",
            action="store_true",
            help="print the current preset as JSON",
        )
        current_parser.add_argument(
            "-s",
            "--save-as",
            metavar="PRESET_NAME",
            help="save the current preset into the user presets directory",
        )
        current_parser.set_defaults(func=self.show_current_preset)

        rename_parser = subparsers.add_parser("rename", help="rename an installed preset")
        rename_group = rename_parser.add_mutually_exclusive_group(required=True)
        rename_group.add_argument(
            "-n",
            "--preset-name",
            help="display name for an installed preset",
        )
        rename_group.add_argument(
            "-p",
            "--preset-path",
            help="absolute path to an installed preset",
        )
        rename_parser.add_argument(
            "--new-name",
            required=True,
            help="new display name",
        )
        rename_parser.set_defaults(func=self.rename_preset)

        remove_parser = subparsers.add_parser("remove", help="remove an installed preset")
        remove_group = remove_parser.add_mutually_exclusive_group(required=True)
        remove_group.add_argument(
            "-n",
            "--preset-name",
            help="display name for an installed preset",
        )
        remove_group.add_argument(
            "-p",
            "--preset-path",
            help="absolute path to an installed preset",
        )
        remove_parser.set_defaults(func=self.remove_preset)

        download_parser = subparsers.add_parser(
            "download",
            help="download a preset from a preset repository",
        )
        download_parser.add_argument(
            "-n",
            "--preset-name",
            required=True,
            help="name of a preset you want to get",
        )
        download_parser.add_argument(
            "-r",
            "--repo-name",
            help="restrict the search to one repository name",
        )
        download_parser.set_defaults(func=self.download_preset)

        repos_parser = subparsers.add_parser("repos", help="manage preset repositories")
        repos_group = repos_parser.add_mutually_exclusive_group()
        repos_group.add_argument(
            "-a",
            "--add",
            nargs=2,
            metavar=("NAME", "URL"),
            help="add a user repository",
        )
        repos_group.add_argument(
            "-r",
            "--remove",
            metavar="NAME",
            help="remove a user repository",
        )
        repos_parser.add_argument(
            "-j",
            "--json",
            action="store_true",
            help="print repositories in JSON format",
        )
        repos_parser.set_defaults(func=self.manage_repos)

        monet_parser = subparsers.add_parser(
            "monet",
            help="generate a Material You preset from an image",
        )
        monet_parser.add_argument(
            "-n",
            "--preset-name",
            required=True,
            help="name for the generated preset",
        )
        monet_parser.add_argument(
            "-p",
            "--image-path",
            required=True,
            help="absolute path to the image",
        )
        monet_parser.add_argument(
            "--tone",
            default=20,
            help="a tone for colors (default: 20)",
        )
        monet_parser.add_argument(
            "--theme",
            choices=["light", "dark"],
            default="light",
            help="light or dark theme (default: light)",
        )
        monet_parser.add_argument(
            "-j",
            "--json",
            action="store_true",
            help="print the generated preset in JSON format",
        )
        monet_parser.set_defaults(func=self.generate_monet)

        access_parser = subparsers.add_parser(
            "access-file",
            help="allow or disallow Gradience to access a file or directory",
        )
        access_parser.add_argument(
            "-l",
            "--list",
            action="store_true",
            help="list allowed directories and files",
        )
        access_group = access_parser.add_mutually_exclusive_group(required=False)
        access_group.add_argument(
            "-a",
            "--allow",
            metavar="PATH",
            help="allow Gradience access to this file or directory",
        )
        access_group.add_argument(
            "-d",
            "--disallow",
            metavar="PATH",
            help="disallow Gradience access to this file or directory",
        )
        access_parser.set_defaults(func=self.access_file)

        overrides_parser = subparsers.add_parser(
            "flatpak-overrides",
            help="enable or disable Flatpak theming",
        )
        overrides_group = overrides_parser.add_mutually_exclusive_group(required=True)
        overrides_group.add_argument(
            "-e",
            "--enable-theming",
            choices=["gtk4", "gtk3", "both"],
            help="enable overrides for Flatpak theming",
        )
        overrides_group.add_argument(
            "-d",
            "--disable-theming",
            choices=["gtk4", "gtk3", "both"],
            help="disable overrides for Flatpak theming",
        )
        overrides_parser.set_defaults(func=self.flatpak_theming)

        restore_parser = subparsers.add_parser(
            "restore",
            help="restore the GTK 4 backup created by Gradience",
        )
        restore_parser.add_argument(
            "--gtk",
            choices=["gtk4"],
            default="gtk4",
            help="restore target (GTK 4 only)",
        )
        restore_parser.set_defaults(func=self.restore_preset)

        reset_parser = subparsers.add_parser(
            "reset",
            help="remove the currently applied Gradience CSS",
        )
        reset_parser.add_argument(
            "--gtk",
            choices=["gtk4", "gtk3", "both"],
            default="both",
            help="targets to reset (default: both)",
        )
        reset_parser.set_defaults(func=self.reset_preset)

        return parser

    def _ensure_preset_layout(self):
        presets_dir = Path(PRESETS_DIR)
        presets_dir.mkdir(parents=True, exist_ok=True)
        for name in ("user", "official", "curated"):
            (presets_dir / name).mkdir(exist_ok=True)

    def _iter_builtin_records(self):
        records = []
        for slug in BUILTIN_PRESET_SLUGS:
            preset = self._load_builtin_preset(slug)
            print(f"{preset = }")
            records.append(
                {
                    "kind": "builtin",
                    "name": preset.display_name,
                    "path": f"{ROOTDIR}/presets/{slug}.json",
                    "repo": "builtin",
                    "slug": slug,
                }
            )
        return records

    def _resolve_builtin_path(self, slug):
            return SCRIPT_DIR / "data" / "presets" / f"{slug}.json"

    def _is_builtin_path(self, preset_path):
        resolved = Path(preset_path).expanduser().resolve()
        return resolved in [self._resolve_builtin_path(slug) for slug in BUILTIN_PRESET_SLUGS ]


    def _load_builtin_preset(self, slug):
        builtin_path = self._resolve_builtin_path(slug)
        return Preset().new_from_path(str(builtin_path))
    def _installed_records(self):
        self._ensure_preset_layout()
        records = []
        presets = PresetUtils().get_presets_list(full_list=True)
        for path, name in sorted(presets.items(), key=lambda item: item[1].lower()):
            preset_path = Path(path)
            records.append(
                {
                    "kind": "installed",
                    "name": name,
                    "path": str(preset_path),
                    "repo": preset_path.parent.name,
                    "slug": preset_path.stem,
                }
            )
        return records

    def _match_records(self, name, include_builtins=True):
        records = self._installed_records()
        if include_builtins:
            records.extend(self._iter_builtin_records())

        needle = name.strip()
        folded = needle.lower()
        slug = to_slug_case(needle)

        exact = [
            record
            for record in records
            if record["name"] == needle or record["slug"] == needle
        ]
        if exact:
            return exact

        folded_matches = [
            record
            for record in records
            if record["name"].lower() == folded or record["slug"].lower() == folded
        ]
        if folded_matches:
            return folded_matches

        return [
            record
            for record in records
            if record["slug"] == slug or record["name"].lower() == slug
        ]

    def _resolve_record(self, name, include_builtins=True):
        matches = self._match_records(name, include_builtins=include_builtins)
        if not matches:
            raise CLIError(f"No preset named '{name}' was found.")
        if len(matches) > 1:
            locations = ", ".join(
                f"{record['name']} [{record['repo']}]"
                for record in matches
            )
            raise CLIError(f"Preset name '{name}' is ambiguous: {locations}")
        return matches[0]

    def _load_record_preset(self, record):
        if record["kind"] == "builtin":
            return self._load_builtin_preset(record["slug"])
        return Preset().new_from_path(record["path"])

    def _custom_repos(self):
        return self.settings.get_mapping("repos")

    def _all_repos(self):
        repos = dict(self._custom_repos())
        repos.update(preset_repos)
        return repos

    def _create_current_preset(self, gtk_target):
        css_path = Path(get_gtk_theme_dir(gtk_target)) / "gtk.css"
        try:
            variables, palette, custom_css = parse_css(str(css_path))
        except OSError as exc:
            raise CLIError(f"Unable to read current {gtk_target} CSS from {css_path}.") from exc

        preset = Preset().new_from_dict(
            {
                "name": f"Current {gtk_target.upper()} Preset",
                "variables": variables,
                "palette": palette,
                "custom_css": {
                    "gtk4": custom_css if gtk_target == "gtk4" else "",
                    "gtk3": custom_css if gtk_target == "gtk3" else "",
                },
            }
        )
        return preset, css_path

    def _apply_enabled_plugins(self, preset):
        enabled_plugins = set(self.settings.get_string_list("enabled-plugins"))
        if not enabled_plugins:
            return 0

        try:
            PluginManager = get_plugin_manager()
        except ModuleNotFoundError:
            self.logging.warning(
                "Skipping plugin application because the 'yapsy' dependency is not installed."
            )
            return 0

        globals_module = sys.modules["gradience.backend.globals"]
        Path(globals_module.user_plugin_dir).mkdir(parents=True, exist_ok=True)

        manager = PluginManager()
        manager.setPluginPlaces(
            [globals_module.user_plugin_dir, globals_module.system_plugin_dir]
        )
        manager.collectPlugins()

        preset_settings = {
            "variables": preset.variables,
            "palette": preset.palette,
            "custom_css": preset.custom_css,
        }

        applied = 0
        for plugin_info in manager.getAllPlugins():
            plugin = plugin_info.plugin_object
            try:
                plugin.activate()
            except Exception as exc:
                self.logging.warning(f"Failed to activate plugin {plugin_info.name}.", exc=exc)
                continue

            if hasattr(plugin, "give_preset_settings"):
                try:
                    plugin.give_preset_settings(preset_settings)
                except Exception as exc:
                    self.logging.warning(
                        f"Failed to pass preset settings to plugin {plugin.plugin_id}.",
                        exc=exc,
                    )

            if getattr(plugin, "plugin_id", None) not in enabled_plugins:
                continue

            if not hasattr(plugin, "apply"):
                self.logging.warning(f"Plugin {plugin.plugin_id} does not implement apply().")
                continue

            try:
                plugin.apply()
            except Exception as exc:
                self.logging.warning(f"Failed to apply plugin {plugin.plugin_id}.", exc=exc)
            else:
                applied += 1

        return applied

    def list_presets(self, args):
        presets_list = self._installed_records()

        if args.json:
            print(json.dumps(presets_list, indent=4))
            return 0

        print("\033[1;37mPreset name\033[0m | \033[1;37mRepo\033[0m | \033[1;37mPreset path\033[0m")
        for record in presets_list:
            print(f"{record['name']} | {record['repo']} | {record['path']}")
        return 0

    def list_builtin_presets(self, args):
        presets_list = self._iter_builtin_records()

        if args.json:
            print(json.dumps(presets_list, indent=4))
            return 0

        print("\033[1;37mPreset name\033[0m | \033[1;37mBuiltin id\033[0m")
        for record in presets_list:
            print(f"{record['name']} | {record['slug']}")
        return 0

    def favorite_presets(self, args):
        add_preset = args.add_preset
        remove_preset = args.remove_preset
        as_json = args.json

        favorite = set(self.settings.get_string_list("favourite"))
        installed_names = {record["name"] for record in self._installed_records()}

        if as_json and not add_preset and not remove_preset:
            print(json.dumps({"favorites": sorted(favorite), "amount": len(favorite)}))
            return 0

        if as_json and (add_preset or remove_preset):
            raise CLIError(
                "JSON output option is not available for --add-preset or --remove-preset."
            )

        if add_preset:
            if add_preset not in installed_names:
                raise CLIError(
                    f"Preset named '{add_preset}' is not installed in Gradience."
                )

            favorite.add(add_preset)
            self.settings.set_string_list("favourite", sorted(favorite))
            self.logging.info(f"Preset {add_preset} has been added to favorites.")
            return 0

        if remove_preset:
            if remove_preset not in favorite:
                raise CLIError(
                    f"Preset named '{remove_preset}' does not exist in the favorites list."
                )

            favorite.remove(remove_preset)
            self.settings.set_string_list("favourite", sorted(favorite))
            self.logging.info(f"Preset {remove_preset} has been removed from favorites.")
            return 0

        self.logging.info("Favorite presets list:")
        for preset in sorted(favorite):
            print(preset)
        self.logging.info(f"Favorites amount: {len(favorite)}")
        return 0

    def import_preset(self, args):
        preset_path = Path(args.preset_path).expanduser()
        output_filename = Path(PRESETS_DIR) / "user" / preset_path.name
        self._ensure_preset_layout()
        self.logging.info(f"Importing preset: {preset_path.name}")

        if preset_path.suffix != ".json":
            raise CLIError("Unsupported preset file format, must be .json")

        try:
            output_filename.write_text(preset_path.read_text(encoding="utf-8"), encoding="utf-8")
        except FileNotFoundError as exc:
            raise CLIError("Preset could not be imported.") from exc

        self.logging.info("Preset imported successfully.")
        return 0

    def apply_preset(self, args):
        if args.preset_name:
            record = self._resolve_record(args.preset_name, include_builtins=True)
            preset = self._load_record_preset(record)
        else:
            preset = Preset().new_from_path(args.preset_path)

        targets = ["gtk4", "gtk3"] if args.gtk == "both" else [args.gtk]
        for target in targets:
            PresetUtils().apply_preset(target, preset)

        plugin_count = 0
        if not args.no_plugins:
            plugin_count = self._apply_enabled_plugins(preset)

        if args.gtk == "both":
            self.logging.info(
                f"Preset {preset.display_name} applied successfully for Gtk 3 and Gtk 4 applications."
            )
        else:
            self.logging.info(
                f"Preset {preset.display_name} applied successfully for {args.gtk.capitalize()} applications."
            )

        if plugin_count:
            self.logging.info(f"Applied {plugin_count} enabled plugin(s).")

        self.logging.info("In order for changes to take full effect, you need to log out.")
        return 0

    def show_current_preset(self, args):
        preset, css_path = self._create_current_preset(args.gtk)

        if args.save_as:
            preset.save_to_file(args.save_as)
            self.logging.info(
                f"Current {args.gtk} preset saved successfully as {args.save_as}."
            )

        if args.json:
            print(preset.get_preset_json(indent=4))
            return 0

        print(f"Source CSS: {css_path}")
        print(f"Preset name: {preset.display_name}")
        print(f"Variables: {len(preset.variables)}")
        custom_css = preset.custom_css.get(args.gtk, "")
        print(f"Custom CSS lines: {len(custom_css.splitlines()) if custom_css else 0}")
        return 0

    def rename_preset(self, args):
        if args.preset_path:
            if self._is_builtin_path(args.preset_path):
                raise CLIError("Builtin presets cannot be renamed.")
            preset = Preset().new_from_path(args.preset_path)
        else:
            record = self._resolve_record(args.preset_name, include_builtins=False)
            preset = self._load_record_preset(record)

        old_name = preset.display_name
        preset.rename(args.new_name)
        self.logging.info(f"Preset '{old_name}' renamed to '{args.new_name}'.")
        return 0

    def remove_preset(self, args):
        if args.preset_path:
            preset_path = Path(args.preset_path).expanduser().resolve()
            if self._is_builtin_path(preset_path):
                raise CLIError("Builtin presets cannot be removed.")
            preset = Preset().new_from_path(str(preset_path))
        else:
            record = self._resolve_record(args.preset_name, include_builtins=False)
            preset_path = Path(record["path"]).resolve()
            preset = self._load_record_preset(record)

        if not preset_path.exists():
            raise CLIError(f"Preset path does not exist: {preset_path}")

        preset_path.unlink()
        self.logging.info(f"Preset {preset.display_name} removed successfully.")
        return 0

    def download_preset(self, args):
        repo_filter = args.repo_name.lower() if args.repo_name else None
        repos = self._all_repos()
        downloader = get_downloader()()

        for repo_name, repo_url in repos.items():
            if repo_filter and repo_name.lower() != repo_filter:
                continue

            try:
                explore_presets, urls = downloader.fetch_presets(repo_url)
            except (GLib.GError, json.JSONDecodeError) as exc:
                raise CLIError(
                    f"An error occurred while fetching presets from repository '{repo_name}'."
                ) from exc

            for (slug, preset_name), preset_url in zip(explore_presets.items(), urls):
                if args.preset_name.lower() not in preset_name.lower():
                    continue

                repo_slug = to_slug_case(repo_name)
                (Path(PRESETS_DIR) / repo_slug).mkdir(parents=True, exist_ok=True)
                self.logging.info(f"Downloading preset: {preset_name}")
                try:
                    downloader.download_preset(preset_name, repo_slug, preset_url)
                except (GLib.GError, json.JSONDecodeError, OSError) as exc:
                    raise CLIError("An error occurred while downloading a preset.") from exc

                self.logging.info("Preset downloaded successfully.")
                return 0

        raise CLIError(f"No presets found with text: {args.preset_name}")

    def manage_repos(self, args):
        repos = self._custom_repos()

        if args.add:
            name, url = args.add
            repos[name] = url
            self.settings.set_mapping("repos", repos)
            (Path(PRESETS_DIR) / to_slug_case(name)).mkdir(
                parents=True,
                exist_ok=True,
            )
            self.logging.info(f"Repository '{name}' added successfully.")
            return 0

        if args.remove:
            if args.remove in preset_repos:
                raise CLIError("Builtin repositories cannot be removed.")
            if args.remove not in repos:
                raise CLIError(f"No user repository named '{args.remove}' was found.")
            repos.pop(args.remove)
            self.settings.set_mapping("repos", repos)
            self.logging.info(f"Repository '{args.remove}' removed successfully.")
            return 0

        builtin_repos = [
            {"name": name, "type": "builtin", "url": url}
            for name, url in sorted(preset_repos.items())
        ]
        user_repos = [
            {"name": name, "type": "user", "url": url}
            for name, url in sorted(repos.items())
        ]
        payload = builtin_repos + user_repos

        if args.json:
            print(json.dumps(payload, indent=4))
            return 0

        print("\033[1;37mRepository\033[0m | \033[1;37mType\033[0m | \033[1;37mURL\033[0m")
        for row in payload:
            print(f"{row['name']} | {row['type']} | {row['url']}")
        return 0

    def generate_monet(self, args):
        # try:
        #     # Monet = get_monet_class()
        # except ModuleNotFoundError as exc:
        #     raise CLIError(
        #         "Monet support requires optional dependencies from requirements.txt."
        #     ) from exc

        # try:
        #     palette = Monet().generate_from_image(args.image_path)
        # except (OSError, ValueError) as exc:
        #     raise CLIError(
        #         "If this is a Flatpak install, try adding the file to the access list with "
        #         "`gradience-cli access-file --allow '/path/to/file'`."
        #     ) from exc
        #
        # props = [args.tone, args.theme]
        #
        # if args.json:
        #     try:
        #         preset = PresetUtils().new_preset_from_monet(
        #             args.preset_name,
        #             palette,
        #             props,
        #             True,
        #         )
        #     except (OSError, AttributeError) as exc:
        #         raise CLIError("Unexpected error while generating preset from Monet palette.") from exc
        #     print(preset.get_preset_json(indent=4))
        #     return 0
        #
        # try:
        #     PresetUtils().new_preset_from_monet(args.preset_name, palette, props)
        # except (OSError, AttributeError) as exc:
        #     raise CLIError("Unexpected error while generating preset from Monet palette.") from exc
        #
        # self.logging.info(
        #     "Preset generated successfully. In order to apply it, use `gradience-cli apply <args>`."
        # )
        return 0

    def access_file(self, args):
        if not args.list and not args.allow and not args.disallow:
            raise CLIError(
                "You need to specify an argument for this command. "
                "Type `gradience-cli access-file --help` to check available arguments."
            )

        tools = get_flatpak_tools()

        if args.list:
            try:
                access_list = tools.list_file_access()
            except GLib.GError as exc:
                raise CLIError("An error occurred while accessing the allowed files list.") from exc

            self.logging.info("Allowed files:")
            if access_list:
                for value in access_list:
                    print(value)
            else:
                print("No paths found.")
            return 0

        if args.allow:
            try:
                tools.allow_file_access(args.allow)
            except GLib.GError as exc:
                raise CLIError("An error occurred while setting file access.") from exc
            self.logging.info(f"Path {args.allow} added to access list.")
            return 0

        if args.disallow:
            try:
                tools.disallow_file_access(args.disallow)
            except GLib.GError as exc:
                raise CLIError("An error occurred while setting file access.") from exc
            self.logging.info(f"Path {args.disallow} removed from access list.")
            return 0

        return 0

    def flatpak_theming(self, args):
        tools = get_flatpak_tools()

        if args.enable_theming in ("gtk4", "gtk3"):
            tools.create_gtk_user_override(self.settings, args.enable_theming)
            self.logging.info(
                f"Flatpak theming for {args.enable_theming.capitalize()} applications has been enabled."
            )
        elif args.enable_theming == "both":
            tools.create_gtk_user_override(self.settings, "gtk4")
            tools.create_gtk_user_override(self.settings, "gtk3")
            self.logging.info("Flatpak theming for Gtk 4 and Gtk 3 applications has been enabled.")

        if args.disable_theming in ("gtk4", "gtk3"):
            tools.remove_gtk_user_override(self.settings, args.disable_theming)
            self.logging.info(
                f"Flatpak theming for {args.disable_theming.capitalize()} applications has been disabled."
            )
        elif args.disable_theming == "both":
            tools.remove_gtk_user_override(self.settings, "gtk4")
            tools.remove_gtk_user_override(self.settings, "gtk3")
            self.logging.info("Flatpak theming for Gtk 4 and Gtk 3 applications has been disabled.")
        return 0

    def restore_preset(self, _args):
        try:
            PresetUtils().restore_gtk4_preset()
        except OSError as exc:
            raise CLIError("Unable to restore GTK 4 backup.") from exc

        self.logging.info("GTK 4 backup restored successfully.")
        self.logging.info("In order for changes to take full effect, you need to log out.")
        return 0

    def reset_preset(self, args):
        targets = ["gtk4", "gtk3"] if args.gtk == "both" else [args.gtk]
        for target in targets:
            try:
                PresetUtils().reset_preset(target)
            except GLib.GError as exc:
                raise CLIError(f"Unable to delete the current preset for {target}.") from exc

        if args.gtk == "both":
            self.logging.info("Current Gtk 4 and Gtk 3 presets removed successfully.")
        else:
            self.logging.info(f"Current {args.gtk} preset removed successfully.")

        self.logging.info("In order for changes to take full effect, you need to log out.")
        return 0

    def run(self, argv=None):
        args = self.parser.parse_args(argv)
        if not args.command:
            print(self.parser.format_help())
            return 0

        try:
            return args.func(args)
        except CLIError as exc:
            self.logging.error(str(exc), exc=exc.__cause__)
            return 1


def main(argv=None, version=None, app_id=None, source_root=None):
    # bootstrap_runtime(version=version, app_id=app_id, source_root=source_root)
    cli = GradienceCLI(version, app_id)
    return cli.run(argv)
