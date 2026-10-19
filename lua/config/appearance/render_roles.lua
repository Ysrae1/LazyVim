local M = {}

-- Theme names are declared here; native behavior is a stable, versioned role.
function M.groups()
  local groups = {}
  local function assign(names, role)
    for _, name in ipairs(names) do groups[name] = { role } end
  end
  assign({ "GlowNotebookLanguage", "GlowNotebookMarkdown" }, "enlarged_icon")
  assign({ "AvanteReversedTitle", "AvanteReversedSubtitle", "AvanteReversedThirdTitle" }, "solid_title_cap")
  -- 底栏端帽外侧使用玻璃底材，内部彩色轮廓仍保持实心。
  assign({ "St_file_sep", "St_Pos_sep", "St_cwd_sep", "St_lsp_sep", "St_sep_r" }, "solid_title_cap")
  for _, mode in ipairs({ "Normal", "Visual", "Insert", "Terminal", "NTerminal", "Replace", "Confirm", "Command", "Select" }) do
    groups["St_" .. mode .. "ModeSep"] = { "solid_title_cap" }
  end
  for _, suffix in ipairs({ "", "Cap", "Value", "ValueCap" }) do
    groups["GlowNotebookKernel" .. suffix] = { "notebook_kernel" }
    groups["GlowNotebookCells" .. suffix] = { "notebook_actions" }
    groups["GlowNotebookMenu" .. suffix] = { "notebook_actions" }
  end
  assign({ "GlowNotebookPrev", "GlowNotebookNext" }, "notebook_actions")
  local references = require("config.appearance.editor_highlights").config.references
  if vim.g.neovide_reference_outline_supported and references.enabled and references.outline then
    assign({ "LspReferenceText", "LspReferenceRead", "LspReferenceWrite" }, "reference_outline")
  end
  return groups
end

function M.setup()
  -- 用户配置可能早于原生能力声明加载；就绪后按当前开关重新声明。
  local group = vim.api.nvim_create_augroup("GlowHighlightRoles", { clear = true })
  if not vim.g.neovide_reference_outline_supported then
    vim.api.nvim_create_autocmd("User", {
      group = group, pattern = "NeovideHighlightRolesReady", once = true, callback = function() M.setup() end,
    })
  end
  local groups = M.groups()
  vim.g.neovide_highlight_roles = groups
  if type(_G.neovide) == "table" and type(_G.neovide.set_highlight_roles) == "function" then
    _G.neovide.set_highlight_roles(groups)
  end
end

return M
