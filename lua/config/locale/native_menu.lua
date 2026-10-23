-- Native menu capability is advertised only by macOS hosts that support it.
local M = {}

function M.refresh(locale)
  if vim.fn.has("macunix") ~= 1 or vim.g.neovide_native_menu_version ~= 1 then return end
  local host = _G.neovide
  if type(host) == "table" and type(host.set_native_menu_language) == "function" then
    host.set_native_menu_language(locale.current())
  end
end

function M.setup(locale)
  local group = vim.api.nvim_create_augroup("GlowNativeMenuLocale", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "GlowLanguageChanged", "NeovideNativeMenuReady" },
    callback = function() M.refresh(locale) end,
  })
  M.refresh(locale)
end

return M
