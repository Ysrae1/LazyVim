-- Both ToggleTerm and Snacks inherit this interpreter. Keep interactive
-- profiles enabled; shellcmdflag only controls Neovim's command jobs.
local M = {}

function M.setup()
  if vim.fn.has("win32") ~= 1 then
    return false
  end
  local shell
  for _, candidate in ipairs({ "pwsh", "powershell" }) do
    if vim.fn.executable(candidate) == 1 then
      shell = candidate
      break
    end
  end
  if not shell then
    return false
  end
  -- Reuse LazyVim's PowerShell encoding, quoting and redirection rules instead
  -- of applying only 'shell' and leaving incompatible cmd.exe command flags.
  require("lazyvim.util.terminal").setup(shell)
  -- $PSStyle only exists in PowerShell 7.2+. LazyVim also selects Windows
  -- PowerShell 5.1, so protect its optional ANSI preference while retaining
  -- the complete UTF-8, quoting and redirection setup for command jobs.
  local assignment = "$PSStyle.OutputRendering='plaintext';"
  local flags = vim.o.shellcmdflag
  local first, last = flags:find(assignment, 1, true)
  if first then
    vim.o.shellcmdflag = flags:sub(1, first - 1)
      .. "if (Get-Variable -Name PSStyle -ErrorAction Ignore) {" .. assignment .. "};"
      .. flags:sub(last + 1)
  end
  -- Remove-Alias is unavailable in Windows PowerShell 5.1; the Alias:
  -- provider supports the same removal through Remove-Item on both versions.
  local removal = "Remove-Alias -Force -ErrorAction SilentlyContinue tee;"
  flags = vim.o.shellcmdflag
  first, last = flags:find(removal, 1, true)
  if first then
    vim.o.shellcmdflag = flags:sub(1, first - 1)
      .. "Remove-Item -LiteralPath Alias:tee -Force -ErrorAction SilentlyContinue;"
      .. flags:sub(last + 1)
  end
  -- Hot-install only the shell selection for future ToggleTerm jobs. Existing
  -- terminal processes and the plugin's window/style settings stay untouched.
  local toggleterm = package.loaded["toggleterm.config"]
  if toggleterm and type(toggleterm.get) == "function" then
    toggleterm.get().shell = vim.o.shell
  end
  return vim.o.shell
end

return M
