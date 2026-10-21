"""Private embedded Yazi colors, derived from the editor's active Base46 palette.

No new colors are mixed here. File names use the existing editor foreground in
light mode; bright syntax accents stay on icons rather than washing out names.
"""
import json
import plistlib
import re
from pathlib import Path


def theme_from_palette(palette):
    ui, syntax = palette["ui"], palette["syntax"]
    if not all(isinstance(color, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", color)
               for table in (ui, syntax) for color in table.values()):
        raise ValueError("Embedded Yazi theme requires RGB colors from the editor")
    fg, bg, panel = ui["white"], syntax["base00"], ui["one_bg"]
    blue, red, green, yellow = ui["blue"], ui["red"], ui["green"], ui["yellow"]
    light = palette["background"] == "light"
    # Light Ayu's yellow is an accent, not a readable filename foreground.
    file_fg = lambda color: fg if light else color
    style = lambda foreground=fg, **extra: {"fg": foreground, **extra}
    selected = style(fg, bg=ui["visual_selection"], bold=True, reversed=False)
    return {
        "flavor": {"dark": "", "light": ""},
        "mgr": {
            "cwd": style(fg), "find_keyword": style(fg, bold=True, underline=True),
            "find_position": style(fg, bold=True), "symlink_target": style(fg, italic=True),
            "marker_copied": style(green, bg=green), "marker_cut": style(red, bg=red),
            "marker_marked": style(blue, bg=blue), "marker_selected": style(yellow, bg=yellow),
            "count_copied": style(bg, bg=green), "count_cut": style(bg, bg=red),
            "count_selected": style(ui["white"] if light else bg, bg=yellow),
            "border_style": style(ui["line"]),
        },
        "tabs": {"active": selected, "inactive": style(fg, bg=panel)},
        "mode": {
            "normal_main": style(fg if light else bg, bg=blue, bold=True),
            "normal_alt": style(fg, bg=panel),
            "select_main": style(fg if light else bg, bg=green, bold=True),
            "select_alt": style(fg, bg=panel),
            "unset_main": style(fg if light else bg, bg=red, bold=True),
            "unset_alt": style(fg, bg=panel),
        },
        "indicator": {"parent": selected, "current": selected, "preview": style(fg, underline=True)},
        "status": {
            "overall": style(fg, bg=panel), "progress_label": style(fg, bold=True),
            "progress_normal": style(blue, bg=panel), "progress_error": style(red, bg=panel),
            "perm_sep": style(fg), "perm_type": style(fg), "perm_read": style(fg),
            "perm_write": style(red), "perm_exec": style(file_fg(green)),
        },
        "pick": {"border": style(blue), "active": selected, "inactive": style(fg)},
        "input": {"border": style(blue), "title": style(fg), "value": style(fg), "selected": selected},
        "confirm": {"border": style(blue), "title": style(fg), "body": style(fg),
                    "list": style(fg), "btn_yes": selected, "btn_no": style(fg)},
        "cmp": {"border": style(blue), "active": selected, "inactive": style(fg)},
        "tasks": {"border": style(blue), "title": style(fg), "hovered": selected},
        "which": {"mask": {"bg": bg}, "cand": style(fg, bold=True), "rest": style(fg),
                  "desc": style(fg), "separator_style": style(fg)},
        "help": {"on": style(fg, bold=True), "run": style(fg), "desc": style(fg),
                 "hovered": selected, "footer": style(fg, bg=panel)},
        "notify": {"title_info": style(file_fg(green)), "title_warn": style(file_fg(yellow)),
                   "title_error": style(red)},
        "spot": {"border": style(blue), "title": style(fg), "tbl_col": style(fg), "tbl_cell": selected},
        "filetype": {"rules": [
            {"url": "*", "is": "orphan", **style(red)},
            {"url": "*/", **style(file_fg(syntax["base0D"]))},
            {"url": "*", "is": "exec", **style(file_fg(green))},
            {"mime": "image/*", **style(file_fg(yellow))},
            {"mime": "{audio,video}/*", **style(file_fg(ui["purple"]))},
            {"mime": "application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}", **style(file_fg(red))},
            {"mime": "application/{pdf,doc,rtf,vnd.*}", **style(file_fg(syntax["base0D"]))},
            {"url": "*", **style(fg)},
        ]},
    }


def tmtheme(palette):
    ui, s = palette["ui"], palette["syntax"]
    scopes = {
        "comment": ui["light_grey"], "string": s["base0B"],
        "constant.numeric, constant.language": s["base09"],
        "keyword, storage": s["base0E"], "entity.name.function, support.function": s["base0D"],
        "entity.name.type, support.type": s["base0A"], "variable.parameter": s["base09"],
        "punctuation": s["base0F"], "invalid": ui["red"],
    }
    settings = [{"settings": {"foreground": s["base05"], "background": s["base00"],
                              "selection": ui["visual_selection"]}}]
    settings += [{"scope": scope, "settings": {"foreground": color}} for scope, color in scopes.items()]
    return plistlib.dumps({"name": "Glow editor " + palette["background"], "settings": settings})


def write_private_theme(source, target, palette_file, dump):
    import tomllib
    palette = json.loads(Path(palette_file).read_text(encoding="utf-8"))
    theme = theme_from_palette(palette)
    original = Path(source) / "theme.toml"
    user = tomllib.loads(original.read_text(encoding="utf-8")) if original.exists() else {}
    # Retain icons, separators, labels and non-color preferences from the base.
    def merge(base, overrides):
        for key, value in overrides.items():
            if isinstance(value, dict) and isinstance(base.get(key), dict):
                merge(base[key], value)
            else:
                base[key] = value
        return base
    result = merge(user, theme)
    preview = Path(target) / "glow-editor.tmTheme"
    if preview.is_symlink():
        preview.unlink()
    preview.write_bytes(tmtheme(palette))
    result["mgr"]["syntect_theme"] = str(preview)
    path = Path(target) / "theme.toml"
    # The base theme may have been linked into the private overlay by Lua.
    if path.is_symlink():
        path.unlink()
    path.write_text("# Private Glow theme: current editor palette; regenerated when Yazi opens.\n" +
                    "\n".join(dump(result)) + "\n", encoding="utf-8")
