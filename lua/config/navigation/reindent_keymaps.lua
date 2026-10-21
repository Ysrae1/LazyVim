-- An explicit code-menu entry for the native = operator. It still uses the
-- buffer's indentexpr/equalprg and normal motion/Visual scope, not a formatter.
local M = {}
local lhs
local descriptions = {
  n = { "Reindent Code", "重新缩进（选择范围）" },
  x = { "Reindent Selection", "重新缩进选中代码" },
}
local function translated(row)
  local locale = require("config.platform.locale")
  if type(locale.translate) == "function" then return locale.translate(row[1], row[2]) end
  -- Existing sessions predating translate() can adopt this module safely too.
  return locale.current() == "zh" and row[2] or row[1]
end
local function update()
  if not lhs then return end
  local changed = false
  for mode, row in pairs(descriptions) do
    local map = vim.fn.maparg(lhs, mode, false, true)
    -- A later user mapping is never overwritten during language refresh.
    if map.rhs == "=" and (map.desc == row[1] or map.desc == row[2]) then
      local label = translated(row)
      if label ~= map.desc then
        vim.keymap.set(mode, lhs, "=", { noremap = true, silent = true, desc = label })
        changed = true
      end
    end
  end
  if changed then
    local cache = package.loaded["which-key.buf"]
    if cache then cache.clear() end
    local state = package.loaded["which-key.state"]
    if state and state.state then state.update() end
  end
end
function M.setup()
  lhs = (vim.g.mapleader or "\\") .. "c="
  for mode, row in pairs(descriptions) do
    vim.keymap.set(mode, lhs, "=", { noremap = true, silent = true, desc = translated(row) })
  end
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("GlowReindentKeymaps", { clear = true }),
    pattern = "GlowLanguageChanged", callback = update,
  })
end
return M
