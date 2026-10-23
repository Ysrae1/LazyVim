local M = {}
local uv = vim.uv or vim.loop
local cached_key, cached_roots
local last_file = {}
local request = 0

local function normalize(path)
  if not path or path == "" or path:match("^%a[%w+.-]*://") then
    return
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
  local parent = uv.fs_realpath(vim.fs.dirname(path))
  path = uv.fs_realpath(path) or (parent and vim.fs.joinpath(parent, vim.fs.basename(path))) or path
  if path == "/" or path:match("^%a:/$") then
    return path
  end
  return (path:gsub("/$", ""))
end

local function contains(root, file)
  if vim.fn.has("win32") == 1 then
    root, file = root:lower(), file:lower()
  end
  local prefix = root:sub(-1) == "/" and root or root .. "/"
  return file == root or file:sub(1, #prefix) == prefix
end

local function history_roots()
  local ok, session = pcall(require, "auto-session")
  local directory = ok and session.get_root_dir() or ""
  local stat = directory ~= "" and uv.fs_stat(directory) or nil
  local stamp = stat and (stat.mtime.sec .. ":" .. stat.mtime.nsec) or ""
  local persistence_ok, persistence = pcall(require, "persistence.config")
  local persistence_dir = normalize(
    (persistence_ok and persistence.options.dir) or (vim.fn.stdpath("state") .. "/sessions")
  )
  local persistence_stat = persistence_dir and uv.fs_stat(persistence_dir) or nil
  local persistence_stamp = persistence_stat
      and (persistence_stat.mtime.sec .. ":" .. persistence_stat.mtime.nsec)
    or ""
  local key = table.concat({ directory, stamp, persistence_dir or "", persistence_stamp, table.concat(vim.v.oldfiles, "\n") }, "\0")
  if key == cached_key then
    return cached_roots
  end

  local excluded = { [normalize("~")] = true, ["/"] = true }
  if ok then
    for _, path in ipairs(require("auto-session.config").suppressed_dirs or {}) do
      local normalized = normalize(path)
      if normalized then
        excluded[normalized] = true
      end
    end
  end
  local roots, seen = {}, {}
  local function add(path)
    path = normalize(path)
    local info = path and uv.fs_stat(path)
    if info and info.type == "directory" and not excluded[path] and not seen[path] then
      seen[path] = true
      roots[#roots + 1] = path
    end
  end
  if directory ~= "" then
    local listed, entries = pcall(require("auto-session.lib").get_session_list, directory)
    if listed then
      for _, entry in ipairs(entries) do
        if entry.display_name_component:match("^/") or entry.display_name_component:match("^%a:[/\\]") then
          add(entry.display_name_component)
        end
      end
    end
  end
  if persistence_stat and persistence_stat.type == "directory" then
    local listed, files = pcall(vim.fn.readdir, persistence_dir)
    if listed then
      for _, name in ipairs(files) do
        if name:match("%.vim$") then
          -- Match persistence.select(): %% separates the branch; % encodes a slash.
          local path = vim.split(name:sub(1, -5), "%%", { plain = true })[1]:gsub("%%", "/")
          if vim.fn.has("win32") == 1 then
            path = path:gsub("^(%w)/", "%1:/")
          end
          if path:match("^/") or path:match("^%a:[/\\]") then
            add(path)
          end
        end
      end
    end
  end
  local checked = {}
  for _, file in ipairs(vim.v.oldfiles) do
    local path = normalize(file)
    local parent = path and vim.fs.dirname(path)
    if parent and not checked[parent] then
      checked[parent] = true
      add(vim.fs.root(path, { ".git" }))
    end
  end
  cached_key, cached_roots = key, roots
  return roots
end

function M.resolve(file, roots)
  file = normalize(file)
  if not file then
    return
  end
  local best
  for _, root in ipairs(roots or history_roots()) do
    root = normalize(root)
    if root and contains(root, file) and (not best or #root > #best) then
      best = root
    end
  end
  return best or vim.fs.dirname(file)
end

local function tree_buffer(buf)
  local filetype = vim.bo[buf].filetype
  local name = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
  return filetype == "neo-tree"
    or filetype == "neo-tree-popup"
    or vim.b[buf].neo_tree_source ~= nil
    or name:match("^neo%-tree .+ %[[^%]]+%]$") ~= nil
end

local function normal_file(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" or tree_buffer(buf) then
    return
  end
  local path = normalize(vim.api.nvim_buf_get_name(buf))
  local stat = path and uv.fs_stat(path)
  return path and (not stat or stat.type == "file") and path or nil
end

function M.sync()
  if vim.api.nvim_win_get_config(0).relative ~= "" then
    return
  end
  local tab, buf = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_buf()
  local file = normal_file(buf)
  if file then
    last_file[tab] = buf
  elseif tree_buffer(buf) then
    buf = last_file[tab]
    file = buf and normal_file(buf)
    if not file then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        buf = vim.api.nvim_win_get_buf(win)
        file = normal_file(buf)
        if file then
          break
        end
      end
    end
  end
  if not file or not package.loaded["neo-tree"] then
    return
  end

  require("neo-tree").ensure_config()
  local state = require("neo-tree.sources.manager").get_state("filesystem", tab)
  -- Keep an explicit path jump while browsing the tree. Returning to an editor
  -- file resumes the existing automatic project/file follow behavior.
  if tree_buffer(vim.api.nvim_get_current_buf()) and state._glow_manual_path then return end
  state._glow_manual_path = nil
  local root = M.resolve(file)
  if not require("neo-tree.ui.renderer").window_exists(state) then
    state.path = root
    state._project_follow_file = nil
    return
  end
  if state.path == root and state._project_follow_file == file then
    return
  end
  -- Avoid Neo-tree's global navigation debounce and delayed reopening/focus changes.
  local scan = state.async_directory_scan
  state.async_directory_scan = "never"
  state.bind_to_cwd = false
  local success, err = pcall(require("neo-tree.sources.filesystem")._navigate_internal, state, root, file, nil, false)
  state.async_directory_scan = scan
  if success then
    state._project_follow_file = file
    require("neo-tree.ui.renderer").focus_node(state, file, true)
  else
    vim.notify("Neo-tree project follow: " .. tostring(err), vim.log.levels.WARN)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("UserNeoTreeProjectRoot", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter", "TabEnter", "SessionLoadPost" }, {
    group = group,
    callback = function()
      request = request + 1
      local current, tab, win = request, vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
      vim.schedule(function()
        if current == request and tab == vim.api.nvim_get_current_tabpage() and win == vim.api.nvim_get_current_win() then
          M.sync()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab in pairs(last_file) do
        if not vim.api.nvim_tabpage_is_valid(tab) then
          last_file[tab] = nil
        end
      end
    end,
  })
  M.sync()
end

return M
