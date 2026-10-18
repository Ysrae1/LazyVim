"""Decorate Yazi previewer rules without replacing their conversion pipelines.

Only the private embedded config is written. Python's standard TOML parser
preserves every effective user option, including previewer args and ordering.
"""
import hashlib
import json
import re
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
    config = tomllib.loads(user_file.read_text()) if user_file.exists() else {}
    defaults = tomllib.loads((bridge / "defaults-26.5.6.toml").read_text())
    plugin = config.setdefault("plugin", {})
    plugin.setdefault("previewers", defaults["plugin"]["previewers"])
    wrapped = {}
    for key in ("prepend_previewers", "previewers", "append_previewers"):
        for rule in plugin.get(key, []):
            run = rule.get("run", "")
            match = re.match(r"\s*([^\s]+)(.*)", run, re.S)
            if not match:
                continue
            original, arguments = match.groups()
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
                sync = re.search(r"--[^\n]*@sync\s+peek\b", custom.read_text()) is not None
            wrapped[entry] = original
            header = "--- @sync peek\n" if sync else ""
            # The hook is installed before require(): custom plugins that cache
            # a local alias to ya.image_show also receive the native function.
            text = header + "local bridge = require('neovide-glow-native-preview')\nbridge:install()\n"
            text += "local original = require(" + json.dumps(original) + ")\nlocal M = {}\n"
            text += "function M:peek(job) return bridge:peek_with(original, job) end\n"
            text += "function M:seek(job) if original.seek then return original:seek(job) end end\nreturn M\n"
            (target / "plugins" / "neovide-glow-native-preview.yazi" / (entry + ".lua")).write_text(text)
    (target / "yazi.toml").write_text("\n".join(dump(config)) + "\n")


if __name__ == "__main__":
    main()
