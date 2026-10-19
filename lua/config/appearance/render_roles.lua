local M = {}

-- Theme names are declared here; native behavior is a stable, versioned role.
function M.groups()
  local groups = {}
  local function assign(names, role)
    for _, name in ipairs(names) do groups[name] = { role } end
  end
  assign({ "GlowNotebookLanguage", "GlowNotebookMarkdown" }, "enlarged_icon")
  assign({ "AvanteReversedTitle", "AvanteReversedSubtitle", "AvanteReversedThirdTitle" }, "solid_title_cap")
  for _, suffix in ipairs({ "", "Cap", "Value", "ValueCap" }) do
    groups["GlowNotebookKernel" .. suffix] = { "notebook_kernel" }
    groups["GlowNotebookCells" .. suffix] = { "notebook_actions" }
    groups["GlowNotebookMenu" .. suffix] = { "notebook_actions" }
  end
  assign({ "GlowNotebookPrev", "GlowNotebookNext" }, "notebook_actions")
  return groups
end

function M.setup()
  local groups = M.groups()
  vim.g.neovide_highlight_roles = groups
  if type(_G.neovide) == "table" and type(_G.neovide.set_highlight_roles) == "function" then
    _G.neovide.set_highlight_roles(groups)
  end
end

return M
