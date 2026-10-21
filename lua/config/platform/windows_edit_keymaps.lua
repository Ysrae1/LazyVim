-- Native Windows editing shortcuts. Keep shell controls, window navigation,
-- completion, GUI zoom and the Mac Command bindings outside this adapter.
local M = {}
local owned = {}

local function windows_gui()
  return vim.fn.has("win32") == 1 and not not vim.g.neovide
end

local function text(en, zh)
  local locale = package.loaded["config.platform.locale"]
  local language = locale and locale.current() or vim.g.glow_ui_language or vim.env.LANG or "en"
  return tostring(language):match("^zh") and zh or en
end

function M.paste()
  local content = vim.fn.getreg("+")
  if content == "" then return end
  if vim.fn.getcmdtype() ~= "" then
    -- Insert as text at the current command-line cursor, without queuing keys
    -- behind a pending Enter or interpreting newlines as command submission.
    local line, pos = vim.fn.getcmdline(), vim.fn.getcmdpos()
    local first = content:match("^[^\r\n]*")
    return vim.fn.setcmdline(line:sub(1, pos - 1) .. first .. line:sub(pos), pos + #first)
  end
  -- nvim_paste handles Select/Visual replacement and terminal bracketed paste.
  -- Its Visual deletion must not replace the OS clipboard via unnamedplus.
  local clipboard, format = vim.o.clipboard, vim.bo.formatoptions
  vim.o.clipboard, vim.bo.formatoptions = "", ""
  local ok, result = pcall(vim.api.nvim_paste, content, true, -1)
  vim.o.clipboard, vim.bo.formatoptions = clipboard, format
  if not ok then error(result) end
  return result
end

local function bind(modes, lhs, rhs, en, zh)
  for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do
    local id = mode .. ":" .. lhs
    local existing = vim.fn.maparg(lhs, mode, false, true)
    local previous = owned[id]
    local same_rhs = previous and type(previous.rhs) == "string" and type(existing.rhs) == "string"
      and vim.api.nvim_replace_termcodes(existing.rhs, true, true, true)
        == vim.api.nvim_replace_termcodes(previous.rhs, true, true, true)
    -- Neovim's shipped Insert Ctrl+S shows signature help; native Windows save
    -- takes this one documented default, but never an arbitrary user mapping.
    local default_save = mode == "i" and lhs == "<C-s>" and existing.buffer == 0
      and existing.desc == "vim.lsp.buf.signature_help()" and type(existing.callback) == "function"
      and debug.getinfo(existing.callback, "S").source:gsub("\\", "/"):match("vim/[_%w/]*defaults")
    if vim.tbl_isempty(existing)
      or default_save or previous and (existing.callback == previous.rhs or same_rhs) then
      vim.keymap.set(mode, lhs, rhs, { silent = true, desc = text(en, zh) })
      owned[id] = { rhs = rhs }
    end
  end
end

function M.configure_multicursors(opts)
  if not windows_gui() then return opts end
  local mouse = require("config.editor.multicursor_mouse")
  opts.normal_keys = opts.normal_keys or {}
  for _, item in ipairs({ { "Mouse", "press" }, { "Drag", "drag" }, { "Release", "release" } }) do
    local key = "<A-Left" .. item[1] .. ">"
    if opts.normal_keys[key] == nil then
      opts.normal_keys[key] = {
        method = mouse[item[2]],
        opts = { desc = item[2] == "press" and text("Add selection with Alt+drag", "Alt＋拖动添加选区") or "" },
      }
    end
  end
  return opts
end

function M.setup()
  if not windows_gui() then return false end
  bind("n", "<C-s>", "<Cmd>write<CR>", "Save File", "保存文件")
  bind("i", "<C-s>", "<C-o><Cmd>write<CR>", "Save File", "保存文件")

  -- Copy/cut only when there is a selection; Ctrl+C keeps its cancel/interrupt
  -- meaning in Normal/Insert/command-line/terminal modes.
  for _, key in ipairs({ "<C-c>", "<C-Insert>" }) do
    bind("x", key, '"+y', "Copy to System Clipboard", "复制到系统剪贴板")
    bind("s", key, '<C-g>"+y', "Copy to System Clipboard", "复制到系统剪贴板")
  end
  bind("x", "<C-x>", '"+d', "Cut to System Clipboard", "剪切到系统剪贴板")
  bind("s", "<C-x>", '<C-g>"+d', "Cut to System Clipboard", "剪切到系统剪贴板")
  for _, key in ipairs({ "<C-v>", "<C-S-v>", "<S-Insert>" }) do
    bind({ "n", "i", "x", "s", "c" }, key, M.paste, "Paste from System Clipboard", "从系统剪贴板粘贴")
  end
  bind("t", "<C-S-v>", M.paste, "Paste from System Clipboard", "从系统剪贴板粘贴")
  bind("t", "<S-Insert>", M.paste, "Paste from System Clipboard", "从系统剪贴板粘贴")
  -- Ctrl+V now pastes in editing modes; Ctrl+Q keeps block selection reachable.
  bind({ "n", "x" }, "<C-q>", "<C-v>", "Select a Text Block", "选择矩形文本块")

  for _, item in ipairs({ { "n", "u", "<C-r>" }, { "i", "<C-o>u", "<C-o><C-r>" },
    { "x", "<Esc>u", "<Esc><C-r>" }, { "s", "<C-g><Esc>u", "<C-g><Esc><C-r>" } }) do
    bind(item[1], "<C-z>", item[2], "Undo Text Edit", "撤销文本编辑")
    bind(item[1], "<C-S-z>", item[3], "Redo Text Edit", "重做文本编辑")
    -- A buffer-local completion Ctrl+Y remains authoritative over this fallback.
    bind(item[1], "<C-y>", item[3], "Redo Text Edit", "重做文本编辑")
  end
  bind("n", "<C-a>", "gg0VG$", "Select All Text", "全选文本")
  bind("i", "<C-a>", "<Esc>gg0VG$", "Select All Text", "全选文本")
  bind("x", "<C-a>", "<Esc>gg0VG$", "Select All Text", "全选文本")
  bind("s", "<C-a>", "<C-g><Esc>gg0VG$", "Select All Text", "全选文本")
  for _, key in ipairs({ "<BS>", "<Del>" }) do
    bind("x", key, '"_d', "Delete Selected Text", "删除所选文本")
    bind("s", key, '<C-g>"_d', "Delete Selected Text", "删除所选文本")
  end

  -- Ctrl+/ is the existing terminal toggle. Ctrl+Shift+/ is emitted as Ctrl+?
  -- (Delete) by the frontend, so use a distinct alphabetic shortcut instead.
  bind("n", "<C-S-c>", '<Cmd>lua require("Comment.api").toggle.linewise.current()<CR>', "Toggle Line Comment", "切换行注释")
  bind("i", "<C-S-c>", '<C-o><Cmd>lua require("Comment.api").toggle.linewise.current()<CR>', "Toggle Line Comment", "切换行注释")
  bind("x", "<C-S-c>", "<Esc><Cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>", "Toggle Selection Comments", "切换所选文本的注释")
  for _, item in ipairs({ { "Mouse", "press" }, { "Drag", "drag" }, { "Release", "release" } }) do
    local method = item[2]
    bind({ "n", "x" }, "<A-Left" .. item[1] .. ">", function()
      require("multicursors") -- Run the plugin's setup before entering its layer.
      require("config.editor.multicursor_mouse")[method]()
    end, "Add Selection with Alt+drag", "Alt＋拖动添加选区")
  end
  local group = vim.api.nvim_create_augroup("GlowWindowsEditKeys", { clear = true })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "GlowLanguageChanged", callback = M.setup })
  return true
end

return M
