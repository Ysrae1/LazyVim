local M = {}

local statuses = {
  Staged = { groups = { "GitSignsAdd", "Added" }, names = { "staged_new", "staged_modified", "staged_deleted" } },
  Modified = { groups = { "GitSignsChange", "Changed" }, names = { "modified" } },
  Deleted = { groups = { "GitSignsDelete", "Removed" }, names = { "deleted" } },
  Renamed = { groups = { "Special", "Directory" }, names = { "renamed" } },
  Untracked = { groups = { "GitSignsAdd", "Added" }, names = { "untracked", "unknown" } },
  Ignored = { groups = { "Comment", "NonText" }, names = { "ignored" } },
}

local function foreground(groups)
  for _, name in ipairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
    if hl.fg or hl.ctermfg then
      return name, { fg = hl.fg, ctermfg = hl.ctermfg }
    end
  end
  local hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false, create = false })
  return "Normal", { fg = hl.fg, ctermfg = hl.ctermfg }
end

function M.apply()
  local highlights = package.loaded["fff.highlights"]
  if not highlights and package.loaded["fff"] then
    -- FFF's lazy setup leaves highlights unloaded until the first picker.
    -- This module only defines colours; loading it does not initialize the index.
    highlights = require("fff.highlights")
  end
  if type(highlights) ~= "table" or type(highlights.setup) ~= "function" then
    return false
  end

  -- Reset FFF's private lookup/blended-colour caches without starting its core.
  highlights.setup()
  -- FFF materializes these foregrounds with `default=true`; replaying setup
  -- alone retains the previous palette (and its initial bold-only defaults).
  for name, sources in pairs({
    FFFFileInfoValue = { "Normal" },
    FFFFileInfoTotalScore = { "Number", "Constant", "Identifier" },
    FFFFileInfoMatchType = { "Special", "Statement", "Keyword" },
  }) do
    local _, attrs = foreground(sources)
    attrs.bold = name ~= "FFFFileInfoValue" or nil
    vim.api.nvim_set_hl(0, name, attrs)
  end
  local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false, create = false })
  for suffix, status in pairs(statuses) do
    local target, attrs = foreground(status.groups)
    vim.api.nvim_set_hl(0, "FFFGit" .. suffix, { link = target })
    vim.api.nvim_set_hl(0, "FFFGitSign" .. suffix, { link = target })
    attrs.bg, attrs.ctermbg = visual.bg, visual.ctermbg
    -- Force replacement: FFF's `default=true` retains colours across Base46 reloads.
    vim.api.nvim_set_hl(0, "FFFGitSign" .. suffix .. "Selected", attrs)
    for _, name in ipairs(status.names) do
      local generated = "FFFGitBorderSelected_" .. name
      if vim.fn.hlexists(generated) == 1 then
        vim.api.nvim_set_hl(0, generated, attrs)
      end
    end
  end

  local target, selected = foreground({ "Directory", "Number" })
  vim.api.nvim_set_hl(0, "FFFSelected", { link = target })
  selected.bg, selected.ctermbg = visual.bg, visual.ctermbg
  vim.api.nvim_set_hl(0, "FFFSelectedActive", selected)
  return true
end

return M
