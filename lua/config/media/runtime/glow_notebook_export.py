"""Validate and stage pinned Molten exports, including explicit output deletion."""
from bisect import bisect_right
from copy import deepcopy
import os
from pathlib import Path
import shutil
import tempfile

import nbformat
from molten import ipynb
from molten.ipynb import compare_contents


def _layout(nvim):
    cells = nvim.exec_lua("""
      local result={}
      for _,cell in ipairs(require('config.media.notebook_edit').cells(0)) do
        if cell.kind=='code' then result[#result+1]={first=cell.first,last=cell.last} end
      end
      return result
    """)
    return cells, [cell["first"] - 1 for cell in cells]


def _source_index(nvim, span, cells, firsts):
    if span.bufno != nvim.current.buffer.number:
        raise RuntimeError("输出属于另一个 Notebook；本次输出保存已停止。")
    row = span.begin.lineno
    index = bisect_right(firsts, row) - 1
    if index >= 0 and row <= cells[index]["last"] - 1:
        return index + 1
    return None


def capture_import(nvim, kernel, filepath):
    path = Path(filepath if str(filepath).endswith(".ipynb") else str(filepath) + ".ipynb")
    if not path.is_file():
        return
    code = [cell for cell in nbformat.read(path, as_version=4).cells if cell.cell_type == "code"]
    cells, firsts = _layout(nvim)
    for span, writer in kernel.outputs.items():
        if span.bufno != nvim.current.buffer.number or not writer.output.old:
            continue
        index = _source_index(nvim, span, cells, firsts)
        if index is not None and index <= len(code):
            writer.output._glow_saved_outputs = deepcopy(code[index - 1].outputs)
            writer.output._glow_saved_execution_count = code[index - 1].execution_count


def export(nvim, kernel, filepath, overwrite, original):
    path = Path(filepath if str(filepath).endswith(".ipynb") else str(filepath) + ".ipynb")
    if not path.is_file():
        return original(nvim, kernel, filepath, overwrite)
    document = nbformat.read(path, as_version=4)
    code = [cell for cell in document.cells if cell.cell_type == "code"]
    language = kernel.runtime.kernel_manager.kernel_spec.language
    # Pinned Molten reports unmatched source via notify_error and returns None,
    # the same return value as success. Refuse that path before acknowledging
    # a save, retaining normal unsaved-buffer protection for the live outputs.
    cells, firsts = _layout(nvim)
    def source_index(span):
        return _source_index(nvim, span, cells, firsts)
    indices = {}
    for span, _writer in sorted(kernel.outputs.items(), key=lambda item: item[0]):
        index = source_index(span)
        if index is None or index > len(code) or not compare_contents(nvim, code[index - 1], span, language):
            raise RuntimeError("输出对应的源码已改变；请重新运行或清除该单元格输出后保存。")
        indices[id(span)] = index
    deleted = [record for record in getattr(kernel, "_glow_deleted_outputs", [])
               if record["buf"] == nvim.current.buffer.number]
    for record in deleted:
        span = record["span"]
        cell_index = source_index(span)
        if cell_index is None or cell_index > len(code) or not compare_contents(nvim, code[cell_index - 1], span, language):
            raise RuntimeError("已清除输出的单元格源码或位置已改变；本次输出保存已停止。")
        cell = code[cell_index - 1]
        cell.outputs, cell.execution_count = [], None
    target = path if overwrite else path.with_name("copy-of-" + path.name)
    descriptor, temporary = tempfile.mkstemp(prefix="." + path.name + ".glow-output-", suffix=".ipynb", dir=path.parent)
    os.close(descriptor)
    staged = Path(temporary)
    try:
        shutil.copy2(path, staged)
        if deleted:
            nbformat.write(document, staged)
        if kernel.outputs:
            # Keep Molten's serializer, but bind its sequential source matcher
            # to the actual source-span ordinal. Identical source cells must
            # retain their own output when an earlier sibling was cleared.
            compare = ipynb.compare_contents
            visited = 0
            def exact_cell(nvim_, notebook_cell, span, language_):
                nonlocal visited
                visited += 1
                return visited == indices[id(span)] and compare(nvim_, notebook_cell, span, language_)
            ipynb.compare_contents = exact_cell
            try:
                original(nvim, kernel, str(staged), True)
            finally:
                ipynb.compare_contents = compare
        serialized = nbformat.read(staged, as_version=4)
        serialized_code = [cell for cell in serialized.cells if cell.cell_type == "code"]
        restored_old = False
        for span, writer in kernel.outputs.items():
            output = writer.output
            if output.old and hasattr(output, "_glow_saved_outputs"):
                cell = serialized_code[indices[id(span)] - 1]
                cell.outputs = deepcopy(output._glow_saved_outputs)
                cell.execution_count = output._glow_saved_execution_count
                restored_old = True
        if restored_old:
            nbformat.write(serialized, staged)
        # Both source matching and output serialization completed before the
        # original is replaced. An exception leaves its prior contents intact.
        nbformat.read(staged, as_version=4)
        os.replace(staged, target)
    finally:
        staged.unlink(missing_ok=True)
    if overwrite and deleted:
        kernel._glow_deleted_outputs = [record for record in kernel._glow_deleted_outputs if record not in deleted]
