-- Molten outputs live outside the source buffer's undo tree. Participate in
-- Neovim's normal unsaved-buffer protection without inserting source text.
local M = {}
local states = {}
local group = vim.api.nvim_create_augroup("GlowNotebookOutputDirty", { clear = false })

local function state(buf)
  return states[buf], vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
end

local function protect(buf, current)
  vim.bo[buf].modified = true
  -- :write can reset modified after BufWritePost returns. Recheck at the next
  -- loop boundary, without resurrecting a successful save or unloaded buffer.
  vim.schedule(function()
    local latest, valid = state(buf)
    if latest == current and valid and latest.dirty then vim.bo[buf].modified = true end
  end)
end

function M.attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if states[buf] then return end
  states[buf] = { revision = 0, dirty = false }
  vim.b[buf].glow_notebook_output_dirty = false
  states[buf].autocmd = vim.api.nvim_create_autocmd("BufModifiedSet", {
    group = group, buffer = buf, callback = function()
      -- Undoing source back to its saved text cannot also undo kernel output.
      -- Successful output export clears dirty before setting nomodified.
      if states[buf] and states[buf].dirty and not vim.bo[buf].modified then
        vim.bo[buf].modified = true
      end
    end,
  })
end

function M.changed(buf)
  local current, valid = state(buf)
  if not current or not valid then return false end
  current.revision, current.dirty = current.revision + 1, true
  vim.b[buf].glow_notebook_output_dirty = true
  protect(buf, current)
  return true
end

-- Capture before the synchronous output export. A callback arriving during the
-- save must remain dirty rather than being acknowledged by an older save.
function M.token(buf)
  local current, valid = state(buf)
  if not current or not valid then return nil end
  return { revision = current.revision, changedtick = vim.api.nvim_buf_get_changedtick(buf) }
end

function M.saved(buf, token)
  local current, valid = state(buf)
  if not current or not valid then return false end
  if not token or token.revision ~= current.revision then
    if current.dirty then protect(buf, current) end
    return false
  end
  current.dirty = false
  vim.b[buf].glow_notebook_output_dirty = false
  -- The source writer has already succeeded. Retain any newer source edits.
  vim.bo[buf].modified = token.changedtick ~= vim.api.nvim_buf_get_changedtick(buf)
  return true
end

function M.failed(buf)
  local current, valid = state(buf)
  if not current or not valid then return false end
  current.dirty = true
  vim.b[buf].glow_notebook_output_dirty = true
  protect(buf, current)
  return true
end

function M.status(buf)
  local current = states[buf]
  return current and { dirty = current.dirty, revision = current.revision } or nil
end

function M.detach(buf)
  local current = states[buf]
  if current and current.autocmd then pcall(vim.api.nvim_del_autocmd, current.autocmd) end
  states[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].glow_notebook_output_dirty = nil end
end

return M
