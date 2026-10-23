local M = {}

-- Resolve relative input against the displayed tree, without shell/glob expansion.
function M.resolve(value, root)
  if type(value) ~= "string" or vim.trim(value) == "" then return end
  value = vim.trim(value)
  local quote = value:sub(1, 1)
  if (quote == '"' or quote == "'") and value:sub(-1) == quote then value = value:sub(2, -2) end
  if value == "" then return end
  local windows = require("neo-tree.utils").is_windows
  local function normalize(path) return vim.fs.normalize(path, { win = windows, expand_env = false }) end
  local path, base = normalize(value), normalize(root or vim.fn.getcwd())
  if windows and path:match("^%a:$") then path = path .. "/" end
  if windows and path:match("^/[^/]") then
    -- A rooted Windows path uses the volume displayed in this tree.
    path = (base:match("^%a:") or base:match("^(//[^/]+/[^/]+)") or "") .. path
  elseif not path:match("^/") and not (windows and path:match("^%a:/")) then
    path = base .. "/" .. path
  end
  path = normalize(path)
  return windows and path:gsub("/", "\\") or path
end

function M.goto_path(state)
  local locale = require("config.platform.locale")
  local winid = state.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  local function submit(value)
    local path = M.resolve(value, state.path)
    if not path then return end
    local stat = (vim.uv or vim.loop).fs_stat(path)
    if not stat or (stat.type ~= "directory" and stat.type ~= "file") then
      vim.notify(locale.t("Path is not a file or directory:") .. " " .. path, vim.log.levels.WARN)
      return
    end
    local root = stat.type == "directory" and path or require("neo-tree.utils").split_path(path)
    -- Input callbacks may run before their floating window closes. Navigate only
    -- after that close, and never reopen a tree which was closed in the meantime.
    vim.schedule(function()
      if not winid or not vim.api.nvim_win_is_valid(winid) or state.winid ~= winid then return end
      state._glow_manual_path = true
      vim.api.nvim_set_current_win(winid)
      require("neo-tree.command").execute({
        source = "filesystem", action = "focus", position = state.current_position or state.window.position,
        dir = root, reveal_file = stat.type == "file" and path or nil,
      })
    end)
  end
  -- Reuse Neo-tree's input styling and close/focus handling, anchored inside
  -- this tree rather than the editor-wide vim.ui.input provider.
  local options = require("neo-tree.ui.popups").popup_options(locale.t("Go to path:"), 10, {
    relative = { type = "win", winid = winid },
    position = { row = math.min(1, math.max(0, vim.api.nvim_win_get_height(winid) - 3)), col = 1 },
    size = { width = math.max(1, vim.api.nvim_win_get_width(winid) - 4) },
  })
  -- Use Neovim's native title/border so the input stays directly relative to
  -- the tree, including a right-hand tree (no nested border-window offsets).
  options.border = { style = options.border.style }
  local input = require("nui.input")(options, { prompt = " ", default_value = state.path, on_submit = submit })
  input.win_config.title = { { " " .. locale.t("Go to path:") .. " ", "NeoTreeFloatTitle" } }
  input.win_config.title_pos = "left"
  require("neo-tree.ui.inputs").show_input(input)
  return input
end

return M
