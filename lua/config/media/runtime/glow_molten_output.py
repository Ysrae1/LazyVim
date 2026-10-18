"""Semantic virtual-output chunks for the pinned Molten provider.

Only the original show_virtual_output call may write an output mark. Its scoped
Nvim proxy colors the pending request, then forwards it once without changing
text, placement, lifecycle, image rendering, or any existing mark.
"""
from functools import wraps
import hashlib
import importlib
import inspect
from pathlib import Path
import re
import sys

import pynvim

PINNED_SHOW_SHA256 = "40485131c52f47aa14edb0ba9eca77b488a38a05819c7cc7ec203ea9073660e2"
NORMAL = "MoltenVirtualText"
PREFIX = "GlowNotebookOutput"
_header = re.compile(r"^(\[OLD\] )?(Out\[[^\]\n]*\]:)( ?)(.*)$")
_info = {"active": False, "error": "adapter not initialized"}


def color_lines(lines, output):
    """Return chunks with byte-for-byte identical joined text, per output state."""
    state = output.status.name
    failed = not output.success
    body_group = PREFIX + "Error" if failed else NORMAL
    status, status_group = {
        "NEW": ("Never Run", PREFIX + "Pending"),
        "HOLD": ("* On Hold", PREFIX + "Pending"),
        "RUNNING": ("... Running", PREFIX + "Running"),
        "DONE": ("✗ Failed", PREFIX + "Failure") if failed else ("✓ Done", PREFIX + "Success"),
    }.get(state, ("", NORMAL))
    result = []
    for index, chunks in enumerate(lines):
        text = "".join(chunk[0] for chunk in chunks)
        match = _header.match(text) if index == 0 else None
        if match and match[4].startswith(status) and status:
            colored = []
            if match[1]: colored.append((match[1], NORMAL))
            colored.extend(((match[2], PREFIX + "Number"), (match[3], NORMAL), (status, status_group)))
            tail = match[4][len(status):]
            if tail: colored.append((tail, NORMAL))
            result.append(colored)
        else:
            result.append([(text, body_group)])
    return result


class _Proxy:
    def __init__(self, target, output):
        self._target, self._output = target, output

    def __getattr__(self, name):
        return getattr(self._target, name)


class _Api(_Proxy):
    def set_extmark(self, namespace, row, col, options, **kwargs):
        if "virt_lines" in options:
            options = dict(options, virt_lines=color_lines(options["virt_lines"], self._output))
        return self._target.set_extmark(namespace, row, col, options, **kwargs)


class _Buffer(_Proxy):
    @property
    def api(self):
        return _Api(self._target.api, self._output)


class _Buffers(_Proxy):
    def __getitem__(self, number):
        return _Buffer(self._target[number], self._output)


class _Nvim(_Proxy):
    @property
    def buffers(self):
        return _Buffers(self._target.buffers, self._output)


def install():
    # The remote host receives every registered plugin path in argv. Import
    # exactly its Molten package, temporarily appending (never prioritizing) its
    # parent. This also works when this adapter is loaded before Molten itself.
    plugin = next((Path(arg) for arg in sys.argv if Path(arg).name == "molten" and Path(arg, "outputbuffer.py").is_file()), None)
    if plugin is None:
        raise RuntimeError("registered Molten package is missing from the Python host")
    directory = str(plugin.parent)
    appended = directory not in sys.path
    if appended: sys.path.append(directory)
    try:
        module = importlib.import_module("molten.outputbuffer")
    finally:
        if appended: sys.path.remove(directory)
    cls = module.OutputBuffer
    original = cls.show_virtual_output
    if getattr(original, "_glow_semantic_output", False): return
    if hashlib.sha256(inspect.getsource(original).encode()).hexdigest() != PINNED_SHOW_SHA256:
        raise RuntimeError("Molten output writer differs from the pinned version; adapter was not applied")

    @wraps(original)
    def show_virtual_output(self, anchor):
        nvim = self.nvim
        self.nvim = _Nvim(nvim, self.output)
        try:
            return original(self, anchor)
        finally:
            self.nvim = nvim

    show_virtual_output._glow_semantic_output = True
    cls.show_virtual_output = show_virtual_output


try:
    install()
    _info = {"active": True, "writer": "pinned Molten show_virtual_output", "version": 1}
except Exception as error:
    _info = {"active": False, "error": str(error)}


@pynvim.function("GlowNotebookOutputAdapterInfo", sync=True)
def adapter_info(_nvim, _args):
    return _info
