local M = {}

-- Resolve the plugin only when the existing <leader>tn mapping is used.
-- Query registered sources instead of rebuilding obsolete builtin definitions.
function M.toggle_null_ls()
  local ok, null_ls = pcall(require, "null-ls")
  if not ok then
    vim.notify("none-ls is not available", vim.log.levels.WARN)
    return
  end

  local sources = null_ls.get_sources()
  if #sources == 0 then
    vim.notify("No none-ls sources are active for the installed tools", vim.log.levels.INFO)
    return
  end

  local any_enabled = false
  for _, source in ipairs(sources) do
    if not source._disabled then
      any_enabled = true
      break
    end
  end

  -- An empty query matches every registered source, including external ones.
  if any_enabled then
    null_ls.disable({})
  else
    null_ls.enable({})
  end
  vim.notify("none-ls " .. (any_enabled and "disabled" or "enabled"))
end

return M
