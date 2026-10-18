-- Only loaded by Neovide's private embedded-Yazi configuration overlay.
local M = {}
local kind = "neovide-glow-preview"

local publish = ya.sync(function(_, action, source, skip, path, area)
  local hovered = cx.active.current.hovered
  if not hovered or tostring(hovered.url) ~= source or cx.active.preview.skip ~= skip then return end
  ps.pub_to(0, kind, { action = action, source = source, path = path, area = area, visible = tostring(cx.layer) == "mgr" })
end)

function M:install()
  if self.installed then return end
  self.installed = true
  -- init.lua alone cannot install this for workers: Yazi creates a fresh slim
  -- Lua VM per asynchronous preview. Every generated proxy installs this same
  -- hook BEFORE requiring its original previewer, including custom modules.
  ya.image_show = function(url, rect)
    local job = self.job
    if not job then return nil, Err("Native image_show requires a preview job") end
    if rect.w == 0 or rect.h == 0 then return ui.Rect { x = rect.x, y = rect.y, w = 0, h = 0 } end
    local info, err = ya.image_info(url)
    if not info then return nil, err end
    local cw, ch = rt.term.cell_size()
    -- Match official Image.max_pixel/pixel_area when the terminal reports
    -- metrics. Neovim PTYs commonly expose no pixel dimensions; use an explicit
    -- 8x16 layout reference then. Native rendering stays strictly inside the
    -- same returned box, leaving room for metadata below mixed image/text.
    if not cw or not ch or cw <= 0 or ch <= 0 then cw, ch = 8, 16 end
    local max_w = math.min(rect.w * cw, rt.preview.max_width)
    local max_h = math.min(rect.h * ch, rt.preview.max_height)
    local factor = math.min(1, max_w / info.w, max_h / info.h)
    local placed = ui.Rect { x = rect.x, y = rect.y,
      w = math.min(rect.w, math.ceil(info.w * factor / cw)),
      h = math.min(rect.h, math.ceil(info.h * factor / ch)),
    }
    publish("preview", tostring(job.file.url), job.skip, tostring(url), {
      x = placed.x, y = placed.y, w = placed.w, h = placed.h,
    })
    -- Preserve the public Rect,error convention. The original previewer still
    -- converts/preloads/seeks and publishes its terminal widgets as usual.
    return placed
  end
end

function M:peek_with(original, job)
  self.job = job
  publish("clear", tostring(job.file.url), job.skip)
  return original:peek(job)
end

function M:setup()
  local redraw, signature = Root.redraw, nil
  Root.redraw = function(root)
    local hovered = cx.active.current.hovered
    local path = hovered and tostring(hovered.url) or ""
    local layer = tostring(cx.layer)
    local current = layer .. "\0" .. path
    if current ~= signature then
      signature = current
      -- Yazi's own dialogs live inside one Neovim terminal window, so Neovim
      -- cannot discover them as floats. Explicitly suppress native overlays.
      ps.pub_to(0, kind, { action = "state", source = path, visible = layer == "mgr" })
    end
    return redraw(root)
  end
end

return M
