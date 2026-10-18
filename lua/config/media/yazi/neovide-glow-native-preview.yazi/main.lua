-- Only loaded by Neovide's private embedded-Yazi configuration overlay.
local M = {}
local kind = "neovide-glow-preview"

local publish = ya.sync(function(_, path, area)
  local hovered = cx.active.current.hovered
  if not hovered or tostring(hovered.url) ~= path then return end
  ps.pub_to(0, kind, { action = "preview", path = path, area = area, visible = tostring(cx.layer) == "mgr" })
end)

function M:peek(job)
  -- Clearing the terminal preview also removes the former chafa error. Pixels
  -- are decoded by Neovide; no terminal graphics adapter or child process runs.
  ya.preview_widget(job, {})
  publish(tostring(job.file.url), { x = job.area.x, y = job.area.y, w = job.area.w, h = job.area.h })
end

function M:seek() end

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
      ps.pub_to(0, kind, { action = "state", path = path, visible = layer == "mgr" })
    end
    return redraw(root)
  end
end

return M
