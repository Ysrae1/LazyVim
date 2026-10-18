-- A scoped adapter for Molten's ImageNvimCanvas, not an image.nvim replacement.
-- File headers supply immediate padding sizes. Decoding and pixels stay in the
-- native asynchronous Neovide image worker; never request data back from the GUI.
local M = {}
local api = {}
local images, active = {}, {}
local next_id, clock, pending, configured = 1000000, 0, false, false
local namespace = vim.api.nvim_create_namespace("glow.molten.images")
-- Created only when the native inline capability is actually used.
local inline_namespace
local inline_outputs, inline_revisions = {}, {}
local cell_metrics
local uv = vim.uv or vim.loop
local MAX_ACTIVE, MAX_RECORDS = 8, 128

local function available()
  return vim.g.neovide_native_image == true and type(vim.g.neovide_channel_id) == "number"
end

local function rpc(method, ...)
  return available() and pcall(vim.rpcnotify, vim.g.neovide_channel_id, "neovide.image." .. method, ...)
end

local function close(image)
  if image.native_id then
    active[image.native_id] = nil
    rpc("close", image.native_id)
    image.native_id, image.geometry = nil, nil
  end
end

local function remove_padding(image)
  if image.padding and vim.api.nvim_buf_is_valid(image.buffer) then
    pcall(vim.api.nvim_buf_del_extmark, image.buffer, namespace, image.padding)
  end
  image.padding, image.padding_height, image.padding_row = nil, nil, nil
end

local function warn(image, message)
  if image.error == message then
    return
  end
  image.error = message
  vim.schedule(function()
    vim.notify("Notebook 图像：" .. message, vim.log.levels.WARN, { title = "Neovide Glow" })
  end)
end

local function u16(bytes, offset, little)
  local a, b = bytes:byte(offset, offset + 1)
  if not b then return nil end
  return little and a + b * 256 or a * 256 + b
end

local function u32(bytes, offset, little)
  local a, b, c, d = bytes:byte(offset, offset + 3)
  if not d then return nil end
  return little and a + b * 256 + c * 65536 + d * 16777216 or a * 16777216 + b * 65536 + c * 256 + d
end

-- Bounded local header inspection, not an image decode. Molten normally emits
-- PNG (including Matplotlib); uncommon formats use a conservative box until the
-- native decoder reports their dimensions.
local function dimensions(path)
  local file = uv.fs_open(path, "r", 438)
  if not file then return nil end
  local bytes = uv.fs_read(file, 32, 0) or ""
  if bytes:sub(1, 2) == "\255\216" then
    bytes = uv.fs_read(file, 65536, 0) or bytes
  end
  uv.fs_close(file)
  if bytes:sub(1, 8) == "\137PNG\13\10\26\10" then
    return u32(bytes, 17), u32(bytes, 21)
  elseif bytes:sub(1, 3) == "GIF" then
    return u16(bytes, 7, true), u16(bytes, 9, true)
  elseif bytes:sub(1, 2) == "BM" then
    local height = u32(bytes, 23, true)
    if height and height > 2147483647 then height = 4294967296 - height end
    return u32(bytes, 19, true), height
  elseif bytes:sub(1, 4) == "\0\0\1\0" then
    local width, height = bytes:byte(7, 8)
    return width == 0 and 256 or width, height == 0 and 256 or height
  elseif bytes:sub(1, 2) == "\255\216" then
    local offset = 3
    while offset < #bytes - 8 do
      if bytes:byte(offset) ~= 255 then break end
      local marker = bytes:byte(offset + 1)
      if marker == 255 then
        offset = offset + 1
      else
        local length = u16(bytes, offset + 2)
        if not length or length < 2 then break end
        if marker >= 192 and marker <= 207 and marker ~= 196 and marker ~= 200 and marker ~= 204 then
          return u16(bytes, offset + 7), u16(bytes, offset + 5)
        end
        offset = offset + length + 2
      end
    end
  elseif bytes:sub(1, 4) == "RIFF" and bytes:sub(9, 12) == "WEBP" and bytes:sub(13, 16) == "VP8X" then
    local a, b, c, d, e, f = bytes:byte(25, 30)
    if f then return a + b * 256 + c * 65536 + 1, d + e * 256 + f * 65536 + 1 end
  end
end

local function find_window(image)
  local current_tab = vim.api.nvim_get_current_tabpage()
  if image.window and vim.api.nvim_win_is_valid(image.window)
      and vim.api.nvim_win_get_buf(image.window) == image.buffer
      and vim.api.nvim_win_get_tabpage(image.window) == current_tab then
    return image.window
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
    if vim.api.nvim_win_get_buf(win) == image.buffer then
      return win
    end
  end
end

function api.image_size(identifier)
  local image = images[identifier]
  if not image then return { width = 0, height = 0 } end
  local win = find_window(image)
  local width = win and vim.api.nvim_win_get_width(win) or math.min(80, vim.o.columns)
  local max_width = math.max(1, math.min(80, width - 2))
  -- Molten reserves a header and an image anchor line inside its height cap.
  local max_height = math.max(1, math.min(28, (tonumber(vim.g.molten_output_win_max_height) or 30) - 2))
  -- Molten also clips the float below the selected source cell to the remaining
  -- screen height. Refit to that actual text area after the window is created.
  if win then max_height = math.max(1, math.min(max_height, vim.api.nvim_win_get_height(win) - 2)) end
  if image.inline and win then
    local info = vim.fn.getwininfo(win)[1] or {}
    max_width = math.max(1, math.min(100, width - (info.textoff or 0) - 3))
    max_height = math.max(1, math.min(28, vim.api.nvim_win_get_height(win) - 4))
  end
  if image.inline then
    if not cell_metrics or not image.width or not image.height then
      return { width = 0, height = 0, render_height = 0 }
    end
    local cell_width, cell_height = cell_metrics[1], cell_metrics[2]
    local factor = math.min(1, max_width * cell_width / image.width, max_height * cell_height / image.height)
    local height = image.height * factor / cell_height
    return { width = image.width * factor / cell_width, height = math.ceil(height), render_height = height }
  end
  if image.width and image.height and image.width > 0 and image.height > 0 then
    -- A grid cell is approximately twice as tall as wide. This determines
    -- padding only: native fit uses the exact renderer cell/pixel dimensions.
    local ratio = image.width / image.height * 2
    local height = math.min(max_height, max_width / ratio)
    return { width = math.max(1, math.ceil(height * ratio)), height = math.max(1, math.ceil(height)) }
  end
  return { width = math.min(max_width, 64), height = math.min(max_height, 20) }
end

local function padding(image)
  if not vim.api.nvim_buf_is_valid(image.buffer) then return end
  local count = vim.api.nvim_buf_line_count(image.buffer)
  local row = math.max(0, math.min(image.y, count - 1))
  local height = api.image_size(image.identifier).height
  if image.padding and image.padding_height == height and image.padding_row == row then return end
  local lines = {}
  for _ = 1, height do lines[#lines + 1] = { { "", "Normal" } } end
  image.padding = vim.api.nvim_buf_set_extmark(image.buffer, namespace, row, 0, {
    id = image.padding, virt_lines = lines, strict = false,
    right_gravity = false, priority = 210,
  })
  image.padding_height, image.padding_row = height, row
end

local function intersects(a, b)
  return a.row < b.row + b.height and b.row < a.row + a.height
      and a.col < b.col + b.width and b.col < a.col + a.width
end

local function border(config, side)
  local chars = config.border
  if type(chars) ~= "table" then return 0 end
  local indices = side == "top" and { 1, 2, 3 } or side == "left" and { 1, 8, 7 }
    or side == "right" and { 3, 4, 5 } or { 5, 6, 7 }
  for _, index in ipairs(indices) do
    local char = chars[index]
    if type(char) == "table" then char = char[1] end
    if char and char ~= "" then return 1 end
  end
  return 0
end

local function inline_changed(buf)
  inline_revisions[buf] = (inline_revisions[buf] or 0) + 1
  vim.schedule(function()
    local ui = package.loaded['config.media.notebook_ui']
    if ui then ui.refresh() end
  end)
end

function M.inline_revision(buf)
  return inline_revisions[buf] or 0
end

function M.clear_inline_output(key)
  local output = inline_outputs[key]
  if not output then return end
  inline_outputs[key] = nil
  for _, identifier in ipairs(output.images) do
    local image = images[identifier]
    if image then close(image); images[identifier] = nil end
  end
  if output.padding and vim.api.nvim_buf_is_valid(output.buffer) then
    pcall(vim.api.nvim_buf_del_extmark, output.buffer, inline_namespace, output.padding)
  end
  inline_changed(output.buffer)
end

local function sync_inline(output)
  if not vim.api.nvim_buf_is_valid(output.buffer) then M.clear_inline_output(output.key); return false end
  local mark = vim.api.nvim_buf_get_extmark_by_id(output.buffer, output.namespace, output.mark, { details = true })
  if #mark == 0 or mark[3].invalid then M.clear_inline_output(output.key); return false end
  local lines, shape = {}, {}
  for _, identifier in ipairs(output.images) do
    local image = images[identifier]
    if image then
      image.inline_offset = #lines
      local size = api.image_size(identifier)
      shape[#shape + 1] = { size.width, size.height, size.render_height }
      for _ = 1, size.height do lines[#lines + 1] = { { '', 'Normal' } } end
    end
  end
  local signature = vim.json.encode({ mark[1], shape })
  if signature ~= output.signature then
    output.signature = signature
    output.padding = vim.api.nvim_buf_set_extmark(output.buffer, inline_namespace, mark[1], 0, {
      id = output.padding, virt_lines = lines, right_gravity = true, strict = false,
    })
    inline_changed(output.buffer)
  end
  return true
end

-- Called by the scoped Python writer instead of its original single request.
-- That exact Molten mark stays authoritative; image rows have a separate owner.
function M.set_inline_output(buf, ns, row, col, options, descriptors, key)
  local mark = vim.api.nvim_buf_set_extmark(buf, ns, row, col, options)
  if not available() or vim.g.neovide_native_image_anchor ~= true or not vim.b[buf].glow_notebook_edit then return mark end
  inline_namespace = inline_namespace or vim.api.nvim_create_namespace('glow.molten.inline')
  local output = inline_outputs[key]
  if output and (output.buffer ~= buf or output.namespace ~= ns) then M.clear_inline_output(key); output = nil end
  output = output or { key = key, buffer = buf, namespace = ns, images = {} }
  inline_outputs[key] = output
  if output.mark and output.mark ~= mark and output.padding then
    pcall(vim.api.nvim_buf_del_extmark, buf, inline_namespace, output.padding)
    output.padding, output.signature = nil, nil
  end
  output.mark = mark
  local keep, identifiers = {}, {}
  for index, descriptor in ipairs(descriptors) do
    local identifier = 'inline:' .. key .. ':' .. index
    api.from_file(descriptor.path, { id = identifier, buffer = buf, y = row })
    local image = images[identifier]
    image.inline, image.owner, image.visible = true, key, true
    keep[identifier] = true; identifiers[#identifiers + 1] = identifier
  end
  for _, identifier in ipairs(output.images) do
    if not keep[identifier] then local image = images[identifier]; if image then close(image); images[identifier] = nil end end
  end
  output.images = identifiers
  sync_inline(output)
  vim.schedule(M.refresh)
  return mark
end

function M.inline_output_marks(buf)
  local result = {}
  for _, output in pairs(inline_outputs) do
    if output.buffer == buf and output.padding and sync_inline(output) then
      local mark = vim.api.nvim_buf_get_extmark_by_id(buf, inline_namespace, output.padding, { details = true })
      if #mark > 0 then result[#result + 1] = { id = output.padding, namespace = inline_namespace,
        row = mark[1], lines = #(mark[3].virt_lines or {}), above = false } end
    end
  end
  return result
end

function M.on_cell_metrics(width, height)
  if type(width) ~= 'number' or type(height) ~= 'number' or width <= 0 or height <= 0
      or width ~= width or height ~= height or width == math.huge or height == math.huge then return end
  if cell_metrics and cell_metrics[1] == width and cell_metrics[2] == height then return end
  cell_metrics = { width, height }
  vim.schedule(M.refresh)
end

local function inline_geometry(image, win)
  if vim.fn.pumvisible() == 1 or vim.api.nvim_get_mode().mode:sub(1, 1) == 'c' then return nil end
  local output = inline_outputs[image.owner]
  local ui = package.loaded['config.media.notebook_ui']
  if not output or not ui or not ui.virtual_output_geometry then return nil end
  local area = ui.virtual_output_geometry(win, image.buffer, inline_namespace, output.padding)
  if not area then return nil end
  local size = api.image_size(image.identifier)
  if size.height == 0 then return nil end
  image.models = image.models or {}
  local view = image.models[win]
  if not view or view.anchor.epoch ~= area.anchor.epoch then
    view = { row = area.row + image.inline_offset, col = area.col,
      width = math.min(size.width, area.width), height = size.render_height,
      clip = area.clip, anchor = area.anchor, zoom = 1, pan_x = 0, pan_y = 0, overlay = false }
    image.models[win] = view
  end
  return view
end

local function geometry(image, win)
  if vim.fn.pumvisible() == 1 or vim.api.nvim_get_mode().mode:sub(1, 1) == "c" then return nil end
  local info = vim.fn.getwininfo(win)[1]
  if not info then return nil end
  local config = vim.api.nvim_win_get_config(win)
  -- This first bridge intentionally uses Molten's real output buffers. Inline
  -- text remains virtual; image padding in a source buffer could reorder another
  -- plugin's virtual rows and is therefore not claimed as supported.
  if config.relative == "" then return nil end
  local mark = image.padding and vim.api.nvim_buf_get_extmark_by_id(image.buffer, namespace, image.padding, {})
  if not mark or #mark == 0 then return nil end
  local position = vim.api.nvim_win_get_position(win)
  local top = position[1] + border(config, "top") + (info.winbar or 0)
  local left = position[2] + border(config, "left") + (info.textoff or 0)
  local bottom = top + info.height
  local screen = vim.fn.screenpos(win, mark[1] + 1, 1)
  if screen.row == 0 then return nil end
  local row = screen.row -- screenpos is 1-based; virtual padding starts one row below it.
  local size = api.image_size(image.identifier)
  -- Never shrink/re-fit a partly visible image into a clipped viewport: that
  -- makes it jump and can cover neighboring text. Hide until its box is visible.
  if row < top or row + size.height > bottom then return nil end
  local view = { row = row, col = left + image.x, width = math.min(size.width, info.width - (info.textoff or 0) - image.x),
    height = size.height, zoom = 1, pan_x = 0, pan_y = 0, overlay = true }
  if view.width <= 0 then return nil end
  -- Native overlays must not paint over completion, prompts or another popup.
  -- The owning output float is excluded; higher unrelated floats temporarily
  -- hide the image and keep the normal editor input/stacking behavior intact.
  for _, other in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if other ~= win then
      local other_config = vim.api.nvim_win_get_config(other)
      if other_config.relative ~= "" and (other_config.zindex or 50) >= (config.zindex or 50) then
        local p = vim.api.nvim_win_get_position(other)
        local bounds = { row = p[1], col = p[2],
          width = vim.api.nvim_win_get_width(other) + border(other_config, "left") + border(other_config, "right"),
          height = vim.api.nvim_win_get_height(other) + border(other_config, "top") + border(other_config, "bottom") }
        if intersects(view, bounds) then return nil end
      end
    end
  end
  return view
end

function M.refresh()
  pending = false
  for _, output in pairs(inline_outputs) do sync_inline(output) end
  local ordered = {}
  for _, image in pairs(images) do
    if image.visible then ordered[#ordered + 1] = image end
  end
  table.sort(ordered, function(a, b) return a.used > b.used end)
  local count = 0
  for _, image in ipairs(ordered) do
    local win = find_window(image)
    if win and not image.inline then padding(image) end
    local view = win and (image.inline and inline_geometry(image, win) or geometry(image, win))
    if view and count < MAX_ACTIVE and not image.error then
      count = count + 1
      if not image.native_id then
        next_id = next_id + 1
        image.native_id = next_id
        active[next_id] = image
        if not rpc("load", next_id, image.path) then
          close(image)
          warn(image, "无法连接原生图像渲染器")
        end
      end
      if image.native_id and not vim.deep_equal(image.geometry, view) then
        rpc("show", image.native_id, view)
        image.geometry = view
      end
    else
      close(image)
    end
  end
end

local function schedule()
  if not pending then
    pending = true
    vim.schedule(M.refresh)
  end
end

function api.from_file(path, opts)
  opts = opts or {}
  local identifier = opts.id or path
  local buffer = tonumber(opts.buffer)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then return identifier end
  clock = clock + 1
  local image = images[identifier]
  if image and (image.path ~= path or image.buffer ~= buffer) then
    close(image)
    remove_padding(image)
    images[identifier] = nil
    image = nil
  end
  if not image then
    local width, height = dimensions(path)
    image = { identifier = identifier, path = path, width = width, height = height, buffer = buffer }
    images[identifier] = image
  end
  image.x, image.y, image.used = math.max(0, tonumber(opts.x) or 0), math.max(0, tonumber(opts.y) or 0), clock
  image.window = type(opts.window) == "number" and opts.window or nil
  -- Bounded metadata retention; pixels are independently capped by MAX_ACTIVE.
  local records, oldest = 0, nil
  for _, candidate in pairs(images) do
    records = records + 1
    if not candidate.visible and candidate ~= image and (not oldest or candidate.used < oldest.used) then oldest = candidate end
  end
  if records > MAX_RECORDS and oldest then
    close(oldest)
    remove_padding(oldest)
    images[oldest.identifier] = nil
  end
  return identifier
end

function api.render(identifier)
  local image = images[identifier]
  if not image then return end
  image.visible = true
  padding(image)
  schedule()
end

function api.clear(identifier)
  local image = images[identifier]
  if not image then return end
  image.visible = false
  close(image)
  remove_padding(image)
end

function api.clear_all()
  for key in pairs(inline_outputs) do M.clear_inline_output(key) end
  for identifier in pairs(images) do api.clear(identifier) end
  images = {}
end

function api.move(identifier, x, y)
  local image = images[identifier]
  if not image then return end
  image.x, image.y = math.max(0, x), math.max(0, y)
  if image.visible then padding(image); schedule() end
end

function M.on_status(id, width, height, err)
  local image = active[id]
  if not image or image.native_id ~= id or not image.visible then return end
  if err and err ~= vim.NIL and err ~= "" then
    close(image)
    warn(image, tostring(err))
    return
  end
  -- Keep the box used by Molten's synchronous layout stable. The decoder can
  -- discover dimensions absent from a rare-format header, but growing padding
  -- here would exceed the output window height Molten already calculated.
  image.decoded_width, image.decoded_height = width, height
  schedule()
end

function M.setup()
  if not available() then return false end
  M.on_cell_metrics(vim.g.neovide_cell_width, vim.g.neovide_cell_height)
  -- Only Molten's loader is redirected; other image plugins keep their API.
  package.loaded["load_image_nvim"] = { image_api = api, image_utils = {} }
  if configured then return true end
  configured = true
  local group = vim.api.nvim_create_augroup("GlowMoltenImages", { clear = true })
  vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized", "VimResized", "TabEnter", "WinEnter", "WinClosed", "BufWinEnter", "BufWinLeave", "TextChanged", "TextChangedI", "ModeChanged", "CompleteChanged", "CompleteDone", "CmdlineEnter", "CmdlineLeave" }, {
    group = group, callback = schedule,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group, callback = function(event)
      for key, output in pairs(inline_outputs) do if output.buffer == event.buf then M.clear_inline_output(key) end end
      for identifier, image in pairs(images) do
        if image.buffer == event.buf then api.clear(identifier); images[identifier] = nil end
      end
    end,
  })
  vim.api.nvim_create_autocmd('TabLeave', { group = group, callback = function()
    for _, image in pairs(images) do close(image) end
  end })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = api.clear_all })
  return true
end

M.image_api = api
return M
