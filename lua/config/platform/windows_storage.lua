local M = {}

function M.setup()
  if vim.fn.has("win32") ~= 1 or not vim.env.LOCALAPPDATA or vim.env.LOCALAPPDATA == "" then
    return false
  end
  -- Encoding an entire profile/file path into a swap filename can exceed the
  -- Windows path limit. Keep an owned, short directory per configuration and
  -- retain the original directories as recovery/fallback locations.
  -- A config-only migration keeps the same undo/swap namespace. The old
  -- profile remains the stable storage identity; no history is moved or lost.
  local storage_identity = vim.env.NEOVIDE_GLOW_LEGACY_CONFIG or vim.fn.stdpath("config")
  local profile = vim.fn.sha256(storage_identity:gsub("\\", "/"):lower()):sub(1, 12)
  local directory = vim.env.LOCALAPPDATA .. "/NeovideGlow/state/" .. profile .. "/swap"
  local ok, err = pcall(vim.fn.mkdir, directory, "p")
  if not ok or vim.fn.isdirectory(directory) ~= 1 then
    vim.notify("Could not prepare Neovide swap directory: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  local function prepend(option, path)
    local values = vim.opt[option]:get()
    if not vim.tbl_contains(values, path) then
      table.insert(values, 1, path)
      vim.opt[option] = values
    end
  end
  -- No trailing //: Neovim uses basename.swp here and handles name collisions.
  prepend("directory", directory)

  -- Persistent undo embeds the absolute source path in its filename too.
  -- The profile-local default can exceed MAX_PATH even for our own themes.
  -- Keep native persistent undo and the old locations as read fallbacks; never
  -- disable undo or relocate the user's edited files to hide a storage error.
  local undo_directory = vim.env.LOCALAPPDATA .. "/NeovideGlow/state/" .. profile .. "/undo"
  local undo_ok, undo_err = pcall(vim.fn.mkdir, undo_directory, "p")
  if undo_ok and vim.fn.isdirectory(undo_directory) == 1 then
    prepend("undodir", undo_directory)
  else
    vim.notify("Could not prepare Neovide undo directory: " .. tostring(undo_err), vim.log.levels.WARN)
  end
  return directory
end

return M
