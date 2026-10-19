"""Track real Molten execution mutations independently of output rendering."""
from functools import wraps
import hashlib
import inspect


_PINNED_TICK = "ccd7433e83b13db3c6b9e4188ce1c2a5b239ca6b128d213cdab5f52485a1d55e"
_PINNED_MESSAGE = "d9fce182c9d1cc01f75635577e1bd23ffbfd73bde1c1e88ff775cae8acdf079c"
_PINNED_DELETE = "8bbde3cc173eef070d4b8d7c4c3aa04055ef5ba636ef4b8019a4aeb66c73ba86"
_PERSISTED_MESSAGES = {
    "execute_input", "execute_result", "error", "stream", "display_data", "clear_output",
}


def install():
    from molten import Molten
    from molten.moltenbuffer import MoltenKernel
    from molten.runtime import JupyterRuntime

    tick, message, delete = MoltenKernel.tick, JupyterRuntime._tick_one, Molten.command_delete
    if getattr(tick, "_glow_output_dirty", False):
        return
    for original, expected in ((tick, _PINNED_TICK), (message, _PINNED_MESSAGE), (delete, _PINNED_DELETE)):
        if hashlib.sha256(inspect.getsource(original).encode()).hexdigest() != expected:
            raise RuntimeError("Molten execution writer differs from the pinned version; dirty tracking was not applied")

    @wraps(message)
    def tick_message(self, output, message_type, content):
        previous_status = output.status
        pending_clear = output._should_clear and bool(output.chunks)
        changed = message(self, output, message_type, content)
        context = getattr(self, "_glow_output_dirty_context", None)
        persisted = changed and (message_type in _PERSISTED_MESSAGES or output.status != previous_status)
        if context is not None and (persisted or pending_clear):
            owner, buffers = context
            for span, output_buffer in owner.outputs.items():
                if output_buffer.output is output:
                    buffers.add(span.bufno)
                    break
        return changed

    @wraps(tick)
    def tick_kernel(self):
        buffers = set()
        previous = getattr(self.runtime, "_glow_output_dirty_context", None)
        self.runtime._glow_output_dirty_context = (self, buffers)
        try:
            return tick(self)
        finally:
            self.runtime._glow_output_dirty_context = previous
            if buffers:
                # Synchronous notification precedes a later :write. A saved
                # revision cannot acknowledge a delayed scheduled callback.
                self.nvim.exec_lua("""
                  local dirty=package.loaded['config.media.notebook_dirty']
                  if dirty then for _,buf in ipairs(...) do dirty.changed(buf) end end
                """, sorted(buffers))

    tick_kernel._glow_output_dirty = True

    @wraps(delete)
    def delete_outputs(self, bang):
        buf = self.nvim.current.buffer.number
        tracked = self.nvim.exec_lua("""
          local dirty=package.loaded['config.media.notebook_dirty']
          return dirty and dirty.status(...)~=nil or false
        """, buf)
        if not tracked:
            return delete(self, bang)
        before = [(kernel, span, span.get_text(self.nvim))
                  for kernel in self.buffers.get(buf, []) for span in kernel.outputs if span.bufno == buf]
        try:
            return delete(self, bang)
        finally:
            removed = False
            for kernel, span, source in before:
                if span in kernel.outputs:
                    continue
                code_index = self.nvim.exec_lua("""
                  local buf,row=...
                  local edit=package.loaded['config.media.notebook_edit']
                  if not edit then return 0 end
                  local index=0
                  for _,cell in ipairs(edit.cells(buf)) do
                    if cell.kind=='code' then
                      index=index+1
                      if row>=cell.first-1 and row<=cell.last-1 then return index end
                    end
                  end
                  return 0
                """, buf, span.begin.lineno)
                records = getattr(kernel, "_glow_deleted_outputs", None)
                if records is None:
                    records = kernel._glow_deleted_outputs = []
                # Retaining the span keeps its DynamicPosition marks alive;
                # a later insertion above the cell cannot retarget its clear.
                records.append({"buf": buf, "span": span, "source": source, "code_index": code_index})
                removed = True
            if removed:
                self.nvim.exec_lua("""
                  local dirty=package.loaded['config.media.notebook_dirty']
                  if dirty then dirty.changed(...) end
                """, buf)

    JupyterRuntime._tick_one = tick_message
    MoltenKernel.tick = tick_kernel
    Molten.command_delete = delete_outputs
