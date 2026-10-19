"""Saved Notebook results through Molten's own output writer, without a kernel."""
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

from molten.images import NoCanvas
from molten.ipynb import handle_output_types
from molten.options import MoltenOptions
from molten.outputbuffer import OutputBuffer
from molten.outputchunks import Output, OutputStatus
from molten.position import Position

_states = {}


def _text(value):
    return "".join(value) if isinstance(value, list) else value


class SavedOutputs:
    def __init__(self, nvim, bufno):
        self.nvim, self.bufno = nvim, bufno
        self.directory = TemporaryDirectory(prefix="glow-saved-output-")
        self.namespace = nvim.api.create_namespace("molten-extmarks")
        self.canvas = NoCanvas()
        self.outputs = {}
        self.records = {}
        self.counter = 0
        self.options = MoltenOptions(nvim)
        # Opening a saved notebook only decodes supported raster data and text.
        # It never invokes LaTeX/Plotly converters or opens saved HTML.
        self.options.auto_open_html_in_browser = False
        self.kernel = SimpleNamespace(options=self.options, runtime=SimpleNamespace(_alloc_file=self.alloc_file))

    @contextmanager
    def alloc_file(self, extension, mode):
        self.counter += 1
        path = Path(self.directory.name) / f"{self.counter}.{extension}"
        with path.open(mode) as stream:
            yield str(path), stream

    def create_output(self, cell):
        output = Output(cell.get("execution_count"))
        output.old, output.success = True, True
        output.status = OutputStatus.DONE
        for original in cell.get("outputs", []):
            data = dict(original)
            if data.get("output_type") == "stream":
                data["text"] = _text(data.get("text", ""))
            elif data.get("output_type") != "error":
                mime = data.get("data", {})
                # Prefer saved PNG/JPEG over text; preserve textual fallback for
                # rich formats requiring an active renderer or external tools.
                safe = {key: _text(mime[key]) for key in
                        ("image/png", "image/jpeg", "image/gif", "image/webp", "text/plain") if key in mime}
                data["data"] = safe
            chunk, success = handle_output_types(self.nvim, data.get("output_type"), self.kernel, data)
            output.chunks.append(chunk)
            output.success &= success
        writer = OutputBuffer(self.nvim, self.canvas, self.namespace, self.options)
        writer.output = output
        return writer

    def drop(self, key):
        writer, _layout = self.outputs.pop(key)
        writer.clear_virt_output(self.bufno)
        writer.clear_float_win()
        if writer.display_buf.valid:
            self.nvim.api.buf_delete(writer.display_buf.number, {"force": True})
        for chunk in writer.output.chunks:
            if hasattr(chunk, "img_path"):
                try:
                    Path(chunk.img_path).unlink(missing_ok=True)
                except OSError:
                    pass  # A pending decoder may still hold it; close cleanup retries.

    def render(self, cells):
        keep = {str(cell["key"]) for cell in cells}
        for key in list(self.outputs):
            if key not in keep:
                self.drop(key)
        for cell in cells:
            key = str(cell["key"])
            if "outputs" in cell:
                self.records[key] = cell
            layout = (int(cell["row"]), self.nvim.current.window.width)
            if key in self.outputs:
                writer, previous = self.outputs[key]
                if previous == layout and writer.virt_text_id is not None:
                    continue
                writer.clear_virt_output(self.bufno)
            else:
                writer = self.create_output(self.records[key])
            writer.virt_hidden = False
            writer.displayed_status = OutputStatus.NEW
            writer.show_virtual_output(Position(self.bufno, layout[0], 0))
            self.outputs[key] = writer, layout
        return len(self.outputs)

    def enter(self, key, row):
        entry = self.outputs.get(str(key))
        if entry is None:
            return False
        writer = entry[0]
        anchor = Position(self.bufno, row, 0)
        writer.show_floating_win(anchor)
        writer.enter(anchor)
        return True

    def clear(self):
        for key in list(self.outputs):
            self.drop(key)
        self.directory.cleanup()


def handle(nvim, args):
    action, bufno, *rest = args
    bufno = int(bufno)
    if action == "clear":
        state = _states.pop(bufno, None)
        if state is not None:
            state.clear()
        return True
    if action == "render":
        state = _states.get(bufno)
        if state is None:
            state = _states[bufno] = SavedOutputs(nvim, bufno)
        return state.render(rest[0])
    if action == "enter":
        state = _states.get(bufno)
        return state.enter(*rest) if state else False
    raise ValueError("Unknown saved output action")
