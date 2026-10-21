"""Decorate Yazi previewer rules without replacing their conversion pipelines.

Only the private embedded config is written. Python's standard TOML parser
preserves every effective user option, including previewer args and ordering.
"""
import hashlib
import json
import re
import shutil
import sys
import tomllib
from pathlib import Path


def literal(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return "[" + ", ".join(literal(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{ " + ", ".join(literal(key) + " = " + literal(item) for key, item in value.items()) + " }"
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def dump(table, path=()):
    lines = ["[" + ".".join(literal(part) for part in path) + "]"] if path else []
    for key, value in table.items():
        if not isinstance(value, dict):
            lines.append(literal(key) + " = " + literal(value))
    for key, value in table.items():
        if isinstance(value, dict):
            lines.extend(["", *dump(value, (*path, key))])
    return lines


def main():
    source, target, bridge = map(Path, sys.argv[1:4])
    user_file = source / "yazi.toml"
    config = tomllib.loads(user_file.read_text(encoding="utf-8")) if user_file.exists() else {}
    defaults = tomllib.loads((bridge / "defaults-26.5.6.toml").read_text(encoding="utf-8"))
    plugin = config.setdefault("plugin", {})
    plugin.setdefault("previewers", defaults["plugin"]["previewers"])
    # A dedicated decoder only for the codec absent from this ImageMagick build.
    # Other selectors and their existing relative priority are unchanged.
    def executable(name):
        return shutil.which(name) or next((str(Path(prefix) / name) for prefix in ("/opt/homebrew/bin", "/usr/local/bin") if (Path(prefix) / name).is_file()), name)

    decoder = "neovide-glow-jxl" + "".join(" --" + option + "=" + json.dumps(executable(name)) for option, name in (
        ("decoder", "djxl"), ("inspector", "jxlinfo"), ("magick", "magick")))
    jxl_rules = [{"mime": "image/jxl", "run": decoder}, {"url": "*.[jJ][xX][lL]", "run": decoder}]
    plugin["prepend_previewers"] = [*jxl_rules, *plugin.get("prepend_previewers", [])]
    # Preview rules are rewritten to proxies below; preloaders keep their own
    # provider entry point and must not share the mutable rule dictionaries.
    plugin["prepend_preloaders"] = [*[dict(rule) for rule in jxl_rules], *plugin.get("prepend_preloaders", [])]
    jxl_dir = target / "plugins/neovide-glow-jxl.yazi"
    if jxl_dir.is_symlink():
        jxl_dir.unlink()
    jxl_dir.mkdir(exist_ok=True)
    shutil.copyfile(bridge / "neovide-glow-jxl.yazi/main.lua", jxl_dir / "main.lua")
    (target / "jxl-work").mkdir(exist_ok=True)
    wrapped = {}
    for key in ("prepend_previewers", "previewers", "append_previewers"):
        for rule in plugin.get(key, []):
            run = rule.get("run", "")
            match = re.match(r"\s*([^\s]+)(.*)", run, re.S)
            if not match:
                continue
            original, arguments = match.groups()
            # Folder.peek already runs on Yazi's main Lua VM. Sending the
            # proxy's ya.sync clear event from there waits on that same VM and
            # stalls directory loading/navigation. Its text preview needs no
            # native image hook; retain the original synchronous entry point.
            if original == "folder":
                continue
            # Avoid recursively decorating a prior private config overlay.
            if original.startswith("neovide-glow-native-preview"):
                raise ValueError("Yazi native preview overlay cannot be used as its own base config")
            entry = "wrap-" + hashlib.sha256(original.encode()).hexdigest()[:16]
            module = "neovide-glow-native-preview." + entry
            rule["run"] = module + arguments
            if entry in wrapped:
                continue
            base, _, sub = original.partition(".")
            custom = source / "plugins" / (base + ".yazi") / ((sub or "main") + ".lua")
            sync = original == "folder"
            if custom.exists():
                sync = re.search(r"--[^\n]*@sync\s+peek\b", custom.read_text(encoding="utf-8")) is not None
            wrapped[entry] = original
            header = "--- @sync peek\n" if sync else ""
            # The hook is installed before require(): custom plugins that cache
            # a local alias to ya.image_show also receive the native function.
            text = header + "local bridge = require('neovide-glow-native-preview')\nbridge:install()\n"
            text += "local original = require(" + json.dumps(original) + ")\nlocal M = {}\n"
            text += "function M:peek(job) return bridge:peek_with(original, job) end\n"
            text += "function M:seek(job) if original.seek then return original:seek(job) end end\nreturn M\n"
            (target / "plugins" / "neovide-glow-native-preview.yazi" / (entry + ".lua")).write_text(text, encoding="utf-8")
    (target / "yazi.toml").write_text("\n".join(dump(config)) + "\n", encoding="utf-8")
    if len(sys.argv) > 4:
        from theme import write_private_theme
        write_private_theme(source, target, sys.argv[4], dump)


if __name__ == "__main__":
    main()
