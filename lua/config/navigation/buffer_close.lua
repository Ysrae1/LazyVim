-- Keep NvChad's save/discard confirmation and special-buffer behavior. Its
-- fixed version can delete a preview twice after bufhidden=wipe, and reports
-- an aborted :confirm bdelete as E516 instead of a normal non-close result.
local M = {}
local api = vim.api
local aborted = {}
local depth = 0

local function pack(...)
  return { n = select("#", ...), ... }
end

local function snapshot()
  return { win = api.nvim_get_current_win(), buf = api.nvim_get_current_buf(),
    view = vim.fn.winsaveview(), last_buf = vim.fn.bufnr("$") }
end

local function restore(saved)
  if not (api.nvim_win_is_valid(saved.win) and api.nvim_buf_is_valid(saved.buf)
    and api.nvim_buf_is_loaded(saved.buf)) then return end
  local placeholder = api.nvim_win_get_buf(saved.win)
  local remove_placeholder = placeholder > saved.last_buf and api.nvim_buf_get_name(placeholder) == ""
    and vim.bo[placeholder].buftype == "" and not vim.bo[placeholder].modified
    and vim.deep_equal(api.nvim_buf_get_lines(placeholder, 0, -1, false), { "" })
  api.nvim_set_current_win(saved.win)
  api.nvim_win_set_buf(saved.win, saved.buf)
  vim.fn.winrestview(saved.view)
  -- Upstream creates :enew before confirming the last file. Remove only that
  -- new empty placeholder after restoring an aborted close, never source data.
  if remove_placeholder then api.nvim_buf_delete(placeholder, {}) end
end

local function closed(buf)
  return not api.nvim_buf_is_valid(buf)
    or (not api.nvim_buf_is_loaded(buf) and not vim.bo[buf].buflisted)
end

function M.setup()
  local tabs = require("nvchad.tabufline")
  M.wrappers = M.wrappers or {}
  for _, name in ipairs({ "close_buffer", "closeAllBufs", "closeBufs_at_direction" }) do
    local original = tabs[name]
    if type(original) == "function" and original ~= M.wrappers[name] then
      local wrapped = function(...)
        local buf = name == "close_buffer" and (select(1, ...) or api.nvim_get_current_buf()) or nil
        -- A queued click can outlive the preview it originally referred to.
        if buf and not api.nvim_buf_is_valid(buf) then return true end
        local saved = snapshot()
        depth = depth + 1
        local result = pack(pcall(original, ...))
        depth = depth - 1
        if result[1] then return unpack(result, 2, result.n) end
        local failure = result[2]
        if failure == aborted then
          if depth > 0 then error(aborted, 0) end
          return false
        end
        -- Match this single-buffer command exactly. Other Vim errors, failed
        -- writes and errors from user autocommands must still reach the user.
        local failed_buf = type(failure) == "string" and not failure:find("\n", 1, true)
          and tonumber(failure:match("Vim%(bdelete%):E516:.-: confirm bd(%d+)$"))
        if buf and failed_buf == buf then
          if closed(buf) then
            vim.cmd.redrawtabline()
            return true
          end
          if vim.bo[buf].modified then
            -- E516 does not prove Cancel: a writer may leave the buffer dirty.
            -- Keep the file open and never clear modified or force deletion.
            restore(saved)
            vim.cmd.redrawtabline()
            -- Abort a close-all/directional loop at the first non-close.
            if depth > 0 then error(aborted, 0) end
            return false
          end
        end
        error(failure, 0)
      end
      M.wrappers[name], tabs[name] = wrapped, wrapped
    end
  end
end

return M
