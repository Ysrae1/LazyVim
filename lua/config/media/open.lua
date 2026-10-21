local function T(text) return require("config.platform.locale").t(text) end
-- File-opening integration shared by Dashboard, pickers, :edit and :buffer.
-- Only binary formats are intercepted; HTML source and Jupytext keep their readers.
local M = {}
local configured, pending = false, {}
local images = { 'png','jpg','jpeg','gif','webp','bmp','tif','tiff','ico' }
local media = { 'pdf','mp3','m4a','aac','wav','aiff','aif','caf','flac','mp4','m4v','mov','mpg','mpeg' }

function M.kind(path)
  if type(path) ~= 'string' or path:match('^%a[%w+.-]*://') then return end
  if type(vim.g.neovide_channel_id) ~= 'number' then return end
  if vim.g.neovide_native_image and require('config.media.image').supports(path) then return 'image' end
  if vim.g.neovide_native_preview then
    local preview = require('config.media.preview')
    local kind = preview.kind(path)
    if kind and kind ~= 'web' and preview.available(kind) then return kind end
  end
end

function M.open(path, opts)
  local kind = M.kind(path)
  if not kind then return false end
  if kind == 'image' then return require('config.media.image').open(path, opts) end
  opts = vim.tbl_extend('force', { command = '' }, opts or {})
  return require('config.media.preview').open(path, opts)
end

local function route(win, buf)
  if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf)
    or vim.api.nvim_win_get_buf(win) ~= buf or vim.api.nvim_win_get_config(win).relative ~= ''
    or vim.bo[buf].modified then return end
  local path = vim.b[buf].glow_native_source or vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' and not vim.b[buf].glow_native_source then return end
  if not M.kind(path) or vim.fn.filereadable(path) ~= 1 then return end
  local ok, result = pcall(M.open, path, { win = win, command = '' })
  if not ok or not result then
    vim.notify(T("Unable to open native preview: ") .. tostring(result), vim.log.levels.WARN, { title = T("Native Preview") })
  end
end

local function schedule(win, buf)
  if pending[win] == buf then return end
  pending[win] = buf
  vim.schedule(function()
    if pending[win] ~= buf then return end
    pending[win] = nil
    route(win, buf)
  end)
end

function M.setup()
  if configured or not vim.g.neovide or type(vim.g.neovide_channel_id) ~= 'number' then return end
  configured = true
  local patterns = {}
  local function add(extensions)
    for _, ext in ipairs(extensions) do
      local kind = require('config.media.preview').kind('file.' .. ext)
      if extensions == images or require('config.media.preview').available(kind) then
        patterns[#patterns + 1] = '*.' .. ext:gsub('%a', function(c) return '[' .. c .. c:upper() .. ']' end)
      end
    end
  end
  if vim.g.neovide_native_image then add(images) end
  if vim.g.neovide_native_preview then add(media) end
  if #patterns == 0 then return end
  local group = vim.api.nvim_create_augroup('GlowNativeFileOpen', { clear = true })
  vim.api.nvim_create_autocmd('BufReadCmd', { group = group, pattern = patterns, callback = function(event)
    -- Do not put binary bytes through filetype detection, LSP, or text previews.
    -- Keep a protected source descriptor for bufadd()/buffer picker navigation.
    local buf = event.buf
    vim.b[buf].glow_native_source = vim.api.nvim_buf_get_name(buf)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
    vim.bo[buf].filetype = 'glow_native_source'
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do schedule(win, buf) end
  end })
  vim.api.nvim_create_autocmd('BufWinEnter', { group = group, callback = function(event)
    local buf = event.buf
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do schedule(win, buf) end
  end })
  vim.api.nvim_create_autocmd('VimEnter', { group = group, callback = function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do schedule(win, vim.api.nvim_win_get_buf(win)) end
  end })
end

return M
