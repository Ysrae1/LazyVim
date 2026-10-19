-- Native image IDs share one RPC namespace per editor route. Keep these ranges
-- compatible with older Glow binaries, whose status callback uses the same split.
local M = {}
local owners = {
  image = { first = 1, last = 999999, module = "config.media.image" },
  molten = { first = 1000001, last = 1999999, module = "config.media.molten_images" },
  yazi = { first = 2000001, last = 9007199254740991, module = "config.media.yazi" },
}
local sequence = {}
M.notebook_limit = 6

local function capacity_available()
  vim.schedule(function()
    local molten = package.loaded["config.media.molten_images"]
    if molten and molten.on_capacity_available then molten.on_capacity_available() end
  end)
end

function M.is_capacity_error(message)
  return type(message) == "string" and (message:find("Image preview capacity reached", 1, true) ~= nil
    or message:find("Too many image previews", 1, true) ~= nil)
end

function M.notify(owner, method, ...)
  assert(owners[owner], "Unknown native image owner: " .. tostring(owner))
  local args = { ... }
  -- Older binaries ignore this optional owner; IDs retain their original split.
  if method == "load" then args[3] = owner end
  local ok = pcall(vim.rpcnotify, vim.g.neovide_channel_id, "neovide.image." .. method, unpack(args))
  if ok and method == "close" and owner ~= "molten" then
    capacity_available()
  end
  return ok
end

function M.allocate(owner)
  local range = assert(owners[owner], "Unknown native image owner: " .. tostring(owner))
  local previous = sequence[owner] or range.first - 1
  -- Never wrap or reuse an ID: a queued status callback can outlive its preview.
  if previous >= range.last then return nil, "图片请求编号已用尽，请重启编辑器会话。" end
  local id = previous + 1
  sequence[owner] = id
  return id
end

function M.on_status(id, ...)
  if type(id) ~= "number" or id ~= math.floor(id) then return end
  for owner, range in pairs(owners) do
    if id >= range.first and id <= range.last then
      local ok, module = pcall(require, range.module)
      if ok and type(module.on_status) == "function" then module.on_status(id, ...) end
      local _, _, err = ...
      if owner ~= "molten" and err and err ~= vim.NIL and err ~= "" and not M.is_capacity_error(err) then
        -- Native decode failures release their slot before delivering status.
        capacity_available()
      end
      return
    end
  end
end

return M
