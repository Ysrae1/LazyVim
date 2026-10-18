-- Native Neovide image preview. Keep the frozen Snacks version: the experimental
-- neovide-image branch predates it and requires an unmerged vim.img API.
-- Like that branch, image transport goes over RPC; decoding belongs to the GUI.
local M = {}
local capsule = require("config.media.capsule")
local views, active = {}, {}
local next_id, pending, configured = 0, false, false
local formats = { png = true, jpg = true, jpeg = true, gif = true, webp = true, bmp = true, tif = true, tiff = true, ico = true }

function M.supports(path)
  return type(path) == "string" and formats[(path:match("%.([^./]+)$") or ""):lower()] == true
end

local function available()
  return vim.g.neovide_native_image == true and type(vim.g.neovide_channel_id) == "number"
end

local function notify(message)
  vim.notify(message, vim.log.levels.WARN, { title = "图片预览" })
end

local function rpc(method, ...)
  if available() then
    return pcall(vim.rpcnotify, vim.g.neovide_channel_id, "neovide.image." .. method, ...)
  end
  return false
end

local function release(view)
  if view.id then
    active[view.id] = nil
    rpc("close", view.id)
    view.id, view.geometry = nil, nil
  end
end

local function message(view, lines)
  if not vim.api.nvim_buf_is_valid(view.buf) then
    return
  end
  vim.bo[view.buf].modifiable = true
  vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
  vim.bo[view.buf].modifiable = false
  vim.bo[view.buf].modified = false
end

-- No filename here: the existing buffer/status line already identifies it.
function M.render_title(view, width)
  local zoom = ("×%.2g"):format(view.zoom or 1)
  local state = view.error and "ERROR" or view.width and zoom or "…"
  local detailed = view.width and not view.error and (state .. (" · %d×%d"):format(view.width, view.height)) or state
  local function layout(compact, dimensions, pan, zoom_keys, status)
    local left, left_width = "", 0
    if status then left, left_width = capsule.format("GlowMediaInfo", compact and "V" or "VIEW", dimensions and detailed or state) end
    local right, right_width = {}, 0
    local function add(group, label, value)
      local text, size = capsule.format("GlowMedia" .. group, label, value)
      right[#right + 1], right_width = text, right_width + size + (#right > 0 and 1 or 0)
    end
    if zoom_keys then add("Action", compact and "Z" or "ZOOM", "+ − · 0") end
    if pan then add("Action", compact and "P" or "PAN", "hjkl") end
    if view.error then add("Menu", compact and "R" or "RETRY", "r") end
    add("Menu", compact and "Q" or "CLOSE", "q")
    return "%#GlowMediaBar# " .. left .. "%=" .. table.concat(right, " ") .. " ",
      left_width + right_width + (status and 3 or 2)
  end
  for _, variant in ipairs({
    { false, true, true, true, true }, { false, false, true, true, true },
    { true, false, true, true, true }, { true, false, false, true, true },
    { true, false, false, false, true }, { true, false, false, false, false },
  }) do
    local result, size = layout(unpack(variant))
    if size <= width then return result end
  end
  return "%#GlowMediaMenuValue#q"
end

local function title(view)
  if not vim.api.nvim_win_is_valid(view.win) then
    return
  end
  vim.wo[view.win].winbar = M.render_title(view, vim.api.nvim_win_get_width(view.win))
end

local function show(view)
  if not view.id or not vim.api.nvim_win_is_valid(view.win) then
    return
  end
  local position = vim.api.nvim_win_get_position(view.win)
  -- The fixed Neovim API height includes winbar; only getwininfo.height is
  -- the text area. Exclude it so native pixels never cover the status line.
  local info = vim.fn.getwininfo(view.win)[1]
  local geometry = {
    row = position[1] + ((info and info.winbar) or 0),
    col = position[2],
    width = vim.api.nvim_win_get_width(view.win),
    height = info and info.height or (vim.api.nvim_win_get_height(view.win) - 1),
    zoom = view.zoom,
    pan_x = view.pan_x,
    pan_y = view.pan_y,
  }
  if not vim.deep_equal(view.geometry, geometry) then
    rpc("show", view.id, geometry)
    view.geometry = geometry
  end
end

local function options(win)
  for key, value in pairs({
    number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0",
    wrap = false, list = false, cursorline = false, cursorcolumn = false,
    spell = false, scrolloff = 0, sidescrolloff = 0,
  }) do
    vim.wo[win][key] = value
  end
  vim.wo[win].fillchars = "eob: "
end

local window_options = { "number", "relativenumber", "signcolumn", "foldcolumn", "wrap", "list", "cursorline", "cursorcolumn", "spell", "scrolloff", "sidescrolloff", "fillchars", "winbar" }

local function remember(win)
  local saved = {}
  for _, key in ipairs(window_options) do
    saved[key] = vim.wo[win][key]
  end
  return saved
end

local function restore(view)
  if vim.api.nvim_win_is_valid(view.win) then
    for key, value in pairs(view.saved or {}) do
      vim.wo[view.win][key] = value
    end
  end
end

function M.refresh()
  pending = false
  local visible = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local path = vim.b[buf].glow_image_path
    if path and vim.api.nvim_win_get_config(win).relative == "" then
      visible[win] = true
      local view = views[win]
      if not view or view.buf ~= buf then
        if view then
          release(view)
          restore(view)
        end
        view = { win = win, buf = buf, path = path, zoom = 1, pan_x = 0, pan_y = 0, saved = remember(win) }
        views[win] = view
      end
      options(win)
      if available() and not view.id then
        next_id = next_id + 1
        view.id, view.width, view.height, view.error = next_id, nil, nil, nil
        active[view.id] = view
        message(view, { "正在加载图片…", "", "q / Esc 关闭；Tab / Shift-Tab 切换标签页。" })
        if not rpc("load", view.id, path) then
          view.error = "无法连接 Neovide 图片预览。"
          message(view, { view.error })
        end
      end
      title(view)
      show(view)
    end
  end
  for win, view in pairs(views) do
    if not visible[win] then
      release(view)
      if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= view.buf then
        restore(view)
        views[win] = nil
      end
    end
  end
end

local function schedule()
  if not pending then
    pending = true
    vim.schedule(M.refresh)
  end
end

-- Called by Neovide after the worker finishes. Closed/replaced requests are ignored.
function M.on_status(id, width, height, err)
  local view = active[id]
  if not view or not vim.api.nvim_win_is_valid(view.win) then
    return
  end
  if err and err ~= vim.NIL and err ~= "" then
    view.error = tostring(err)
    message(view, { "图片加载失败", "", view.error, "", "r 重试；q / Esc 关闭。" })
    notify(view.error)
  else
    view.width, view.height, view.error = width, height, nil
    message(view, {})
  end
  title(view)
  show(view)
end

function M.zoom(factor)
  local view = views[vim.api.nvim_get_current_win()]
  if view then
    view.zoom = math.max(0.1, math.min(32, view.zoom * factor))
    title(view)
    show(view)
  end
end

function M.fit()
  local view = views[vim.api.nvim_get_current_win()]
  if view then
    view.zoom, view.pan_x, view.pan_y = 1, 0, 0
    title(view)
    show(view)
  end
end

function M.pan(x, y)
  local view = views[vim.api.nvim_get_current_win()]
  if view and view.width and view.height then
    view.pan_x = math.max(-view.width, math.min(view.width, view.pan_x + x * view.width * 0.05))
    view.pan_y = math.max(-view.height, math.min(view.height, view.pan_y + y * view.height * 0.05))
    show(view)
  end
end

function M.retry()
  local view = views[vim.api.nvim_get_current_win()]
  if view then
    release(view)
    M.refresh()
  end
end

function M.close()
  local win = vim.api.nvim_get_current_win()
  local view = views[win]
  if view then
    release(view)
    restore(view)
    views[win] = nil
  end
  if #vim.api.nvim_tabpage_list_wins(0) > 1 then
    vim.api.nvim_win_close(win, false)
  else
    vim.cmd.enew()
    if view then
      restore(view)
    end
  end
end

local function buffer(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].glow_image_path == path then
      return buf
    end
  end
  local buf = vim.api.nvim_create_buf(true, true)
  local name = vim.fn.bufnr(path) == -1 and path or ("glow-image://" .. path)
  vim.api.nvim_buf_set_name(buf, name)
  vim.b[buf].glow_image_path = path
  vim.bo[buf].filetype = "glow_image"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  local function map(lhs, callback, desc)
    vim.keymap.set("n", lhs, callback, { buffer = buf, silent = true, desc = desc })
  end
  map("+", function() M.zoom(1.25) end, "放大图片")
  map("=", function() M.zoom(1.25) end, "放大图片")
  map("-", function() M.zoom(0.8) end, "缩小图片")
  map("0", M.fit, "图片适应窗口")
  map("f", M.fit, "图片适应窗口")
  map("h", function() M.pan(-1, 0) end, "图片向左平移")
  map("l", function() M.pan(1, 0) end, "图片向右平移")
  map("k", function() M.pan(0, -1) end, "图片向上平移")
  map("j", function() M.pan(0, 1) end, "图片向下平移")
  map("r", M.retry, "重新加载图片")
  map("q", M.close, "关闭图片预览")
  map("<Esc>", M.close, "关闭图片预览")
  map("<Tab>", "gt", "下一个标签页")
  map("<S-Tab>", "gT", "上一个标签页")
  return buf
end

-- Options are intentionally small; Neo-tree supplies its chosen window and split.
function M.open(path, opts)
  opts = opts or {}
  if not available() then
    notify("当前 Neovide 未提供原生图片预览；请使用本项目新构建。")
    return false
  end
  if not M.supports(path) then
    notify("暂不支持该图片格式。支持 PNG、JPEG、GIF（首帧）、WebP、BMP、TIFF、ICO。")
    return false
  end
  M.setup()
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  if opts.win and vim.api.nvim_win_is_valid(opts.win) then
    vim.api.nvim_set_current_win(opts.win)
  end
  if opts.command then
    vim.cmd(opts.command)
  end
  local win = vim.api.nvim_get_current_win()
  local previous = views[win]
  local saved = previous and previous.saved or remember(win)
  if previous then
    release(previous)
  end
  local buf = buffer(path)
  vim.api.nvim_win_set_buf(win, buf)
  views[win] = { win = win, buf = buf, path = path, zoom = 1, pan_x = 0, pan_y = 0, saved = saved }
  M.refresh()
  return true
end

function M.from_tree(event)
  if not vim.g.neovide or not M.supports(event.path) then
    return
  end
  if not available() then
    M.open(event.path)
    return { handled = true }
  end
  local state = event.state
  local win, is_tree = require("neo-tree.utils").get_appropriate_window(state)
  local cmd = event.open_cmd or "edit"
  local split = ({ split = "split", sp = "split", sb = "split", vsplit = "vsplit", vs = "vsplit", ["vert sb"] = "vsplit", tabnew = "tabnew", tabedit = "tabnew" })[cmd]
  if not split and is_tree then
    split = state.current_position == "right" and "leftabove vnew" or "rightbelow vnew"
  end
  local ok, err = pcall(M.open, event.path, { win = win, command = split })
  if not ok then
    notify("无法打开图片预览：" .. tostring(err))
  end
  return { handled = true }
end

function M.setup()
  if configured then
    return
  end
  configured = true
  capsule.refresh_colors()
  local group = vim.api.nvim_create_augroup("GlowNativeImage", { clear = true })
  local function refresh_theme()
    capsule.refresh_colors()
    schedule()
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = refresh_theme })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "NvThemeReload", callback = refresh_theme })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave", "WinEnter", "WinClosed", "WinResized", "VimResized", "WinScrolled", "TabEnter" }, {
    group = group,
    callback = schedule,
  })
  vim.api.nvim_create_autocmd({ "TabLeave", "VimLeavePre" }, {
    group = group,
    callback = function()
      for _, view in pairs(views) do
        release(view)
      end
    end,
  })
  vim.api.nvim_create_user_command("GlowImage", function(args)
    M.open(args.args ~= "" and args.args or vim.api.nvim_buf_get_name(0))
  end, { nargs = "?", complete = "file", desc = "在 Neovide 内预览图片" })
end

return M
