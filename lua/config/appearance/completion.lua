local M = {}

local function has_highlight(name)
  return next(vim.api.nvim_get_hl(0, { name = name, link = false, create = false })) ~= nil
end

local function link(target, source)
  if has_highlight(source) then
    vim.api.nvim_set_hl(0, target, { link = source })
  end
end

function M.apply()
  -- Bridge the Base46 completion palette without requiring a completion plugin.
  local completion = {
    BlinkCmpLabel = "CmpItemAbbr",
    BlinkCmpLabelMatch = "CmpItemAbbrMatch",
    BlinkCmpLabelDeprecated = "CmpItemAbbrDeprecated",
    BlinkCmpLabelDetail = "CmpItemMenu",
    BlinkCmpLabelDescription = "CmpItemMenu",
    BlinkCmpSource = "CmpItemMenu",
    BlinkCmpMenu = "CmpPmenu",
    BlinkCmpMenuBorder = "CmpBorder",
    BlinkCmpMenuSelection = "CmpSel",
    BlinkCmpDoc = "CmpDoc",
    BlinkCmpDocBorder = "CmpDocBorder",
    BlinkCmpDocSeparator = "CmpDocBorder",
    BlinkCmpSignatureHelp = "CmpDoc",
    BlinkCmpSignatureHelpBorder = "CmpDocBorder",
  }
  for target, source in pairs(completion) do
    link(target, source)
  end
  for source in pairs(vim.api.nvim_get_hl(0, {})) do
    local kind = source:match("^CmpItemKind(.+)$")
    if kind then
      link("BlinkCmpKind" .. kind, source)
    end
  end

  link("IblIndent", "IblChar")
  link("IblScope", "IblScopeChar")
  -- IBL copies configured groups into generated highlights, so refresh an
  -- already-loaded instance after changing its input groups.
  local ibl = package.loaded["ibl.highlights"]
  if type(ibl) == "table" and type(ibl.setup) == "function" then
    ibl.setup()
  end

  -- Highlight names are case-insensitive: Base46's DapBreakPointRejected
  -- already resolves as DapBreakpointRejected. Linking them would self-link.
  for _, sign in ipairs(vim.fn.sign_getdefined()) do
    if sign.name:match("^Dap") and has_highlight(sign.name) then
      local options = vim.deepcopy(sign)
      options.name = nil
      options.texthl = sign.name
      vim.fn.sign_define(sign.name, options)
    end
  end
end

return M
