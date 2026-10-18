"""Semantic virtual-output chunks for the pinned Molten provider.

Only the original show_virtual_output call may write an output mark. Its scoped
Nvim proxy colors that pending request without changing its text or placement.
Native image descriptors reserve separate padding owned by that exact mark;
the original floating image provider remains available.
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
    def __init__(self, target, output, nvim=None, buffer=None):
        self._target, self._output = target, output
        self._nvim, self._buffer = nvim, buffer

    def __getattr__(self, name):
        return getattr(self._target, name)


class _Api(_Proxy):
    def set_extmark(self, namespace, row, col, options, **kwargs):
        if "virt_lines" in options:
            options = dict(options, virt_lines=color_lines(options["virt_lines"], self._output))
            images = [{"path": chunk.img_path} for chunk in self._output.chunks if hasattr(chunk, "img_path")]
            if images and self._nvim is not None:
                # Keep the original output request/text intact. The native
                # adapter owns separate image padding linked to this mark.
                return self._nvim.exec_lua("""
                  local buf,ns,row,col,opts,images,key=...
                  local bridge=package.loaded['config.media.molten_images']
                  if bridge and bridge.set_inline_output then
                    return bridge.set_inline_output(buf,ns,row,col,opts,images,key)
                  end
                  return vim.api.nvim_buf_set_extmark(buf,ns,row,col,opts)
                """, self._buffer, namespace, row, col, options, images, str(id(self._output)))
        return self._target.set_extmark(namespace, row, col, options, **kwargs)


class _Buffer(_Proxy):
    @property
    def api(self):
        return _Api(self._target.api, self._output, self._nvim, self._target.number)


class _Buffers(_Proxy):
    def __getitem__(self, number):
        return _Buffer(self._target[number], self._output, self._nvim)


class _Nvim(_Proxy):
    @property
    def buffers(self):
        return _Buffers(self._target.buffers, self._output, self._target)


def _export_without_duplicate_error_fields(original):
    @wraps(original)
    def export_outputs(nvim, kernel, filepath, overwrite):
        restored = []
        try:
            for output in kernel.outputs.values():
                for chunk in output.output.chunks:
                    # Pinned Molten imports the complete notebook error dict
                    # into extras, then supplies output_type/data again as
                    # positional new_output arguments during export.
                    if chunk.output_type != "error":
                        continue
                    duplicate = {"output_type", "data"}
                    if chunk.jupyter_metadata is not None:
                        duplicate.add("metadata")
                    if duplicate.intersection(chunk.extras):
                        restored.append((chunk, chunk.extras))
                        chunk.extras = {key: value for key, value in chunk.extras.items() if key not in duplicate}
            return original(nvim, kernel, filepath, overwrite)
        finally:
            for chunk, extras in restored:
                chunk.extras = extras

    export_outputs._glow_imported_error_export = True
    return export_outputs


def _main_thread_position_destructor(original):
    @wraps(original)
    def destroy(self):
        # Jupyter launch/shutdown threads may collect an old cell. Its original
        # finalizer deletes an extmark synchronously, which pynvim forbids away
        # from its host loop. Retain the position until that loop cleans it up.
        if self.nvim._thread_invalid():
            return self.nvim.async_call(original, self)
        return original(self)

    destroy._glow_main_thread_cleanup = True
    return destroy


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
        ipynb = importlib.import_module("molten.ipynb")
        package = importlib.import_module("molten")
        position = importlib.import_module("molten.position")
    finally:
        if appended: sys.path.remove(directory)
    cls = module.OutputBuffer
    original = cls.show_virtual_output
    if getattr(original, "_glow_semantic_output", False): return
    if hashlib.sha256(inspect.getsource(original).encode()).hexdigest() != PINNED_SHOW_SHA256:
        raise RuntimeError("Molten output writer differs from the pinned version; adapter was not applied")

    if not getattr(ipynb.export_outputs, "_glow_imported_error_export", False):
        original_export = ipynb.export_outputs
        ipynb.export_outputs = _export_without_duplicate_error_fields(original_export)
        # The command module imports this function by name; retain its exact
        # matching/export/error handling and wrap only that existing binding.
        if getattr(package, "export_outputs", None) is original_export:
            package.export_outputs = ipynb.export_outputs

    destructor = position.DynamicPosition.__del__
    if not getattr(destructor, "_glow_main_thread_cleanup", False):
        position.DynamicPosition.__del__ = _main_thread_position_destructor(destructor)

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
    original_clear = cls.clear_virt_output

    @wraps(original_clear)
    def clear_virt_output(self, bufnr):
        try:
            return original_clear(self, bufnr)
        finally:
            self.nvim.exec_lua("""
              local bridge=package.loaded['config.media.molten_images']
              if bridge and bridge.clear_inline_output then bridge.clear_inline_output(...) end
            """, str(id(self.output)))

    cls.clear_virt_output = clear_virt_output


try:
    install()
    _info = {"active": True, "writer": "pinned Molten show_virtual_output", "version": 1}
except Exception as error:
    _info = {"active": False, "error": str(error)}


@pynvim.function("GlowNotebookOutputAdapterInfo", sync=True)
def adapter_info(_nvim, _args):
    return _info
