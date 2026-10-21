-- UI adapters for the pinned NeoTree version. Command IDs and paths are intact.
local M = {}
local function L() return require("config.platform.locale") end
local function T(text) return L().t(text) end

function M.prompt(text)
  if L().current() ~= "zh" then return text end
  local name = text:match('^Enter new name for "(.*)":$')
  if name then return '为“' .. name .. '”输入新名称：' end
  name = text:match('^Enter new base name for "(.*)":$')
  if name then return '为“' .. name .. '”输入新名称（保留扩展名）：' end
  name = text:match('^Enter name for new file or directory %(dirs end with a (.*)%):$')
  if name then return '输入新文件或文件夹名称（文件夹名称以 ' .. name .. ' 结尾）：' end
  name = text:match('^(.*) already exists%. Please enter a new name: ?$')
  if name then return '“' .. name .. '”已存在。请输入新名称：' end
  name = text:match("^Are you sure you want to delete '(.*)'%?$")
  if name then return '确定删除“' .. name .. '”？' end
  local count = text:match('^Are you sure you want to delete (%d+) items%?$')
  if count then return '确定删除 ' .. count .. ' 个项目？' end
  if text:sub(1, 24) == 'WARNING: Dir not empty! ' then
    return '文件夹不为空！' .. M.prompt(text:sub(25))
  end
  name = text:match('^(.*) has been modified%. Save under new name%? %(y/n%) ?$')
  if name then return '“' .. name .. '”已修改。以新名称存储？(y/n)' end
  return T(text)
end

local function setup_hidden_count()
  local components = require("neo-tree.sources.common.components")
  if components._glow_hidden_count_locale then return end
  local original = components.name
  components.name = function(config, node, state)
    local result = original(config, node, state)
    -- This exact synthetic message-node suffix/type belongs to NeoTree's
    -- create_nodes(), rather than a file which happens to have the same name.
    if type(result) == "table" and node.type == "message"
      and tostring(node:get_id()):match("_hidden_message$") then
      local count = node.name:match("^%((%d+) hidden items?%)$")
      local forced = node.name:match("^%(forced to show (%d+) hidden items?%)$")
      if count or forced then
        local template = forced and "(forced to show %d hidden items)" or "(%d hidden items)"
        result.text = L().current() == "zh"
          and (T(template):format(tonumber(count or forced)) .. result.text:sub(#node.name + 1)) or result.text
      end
    end
    return result
  end
  components._glow_hidden_count_locale = true
end

function M.setup()
  setup_hidden_count()
  local input = require("neo-tree.ui.inputs")
  if input._glow_ui_locale then return end
  input._glow_ui_locale = true
  local original_input = input.input
  input.input = function(message, ...)
    return original_input(M.prompt(message), ...)
  end
  local confirm = input.confirm
  input.confirm = function(message, callback)
    return confirm(M.prompt(message), callback)
  end
  local popups = require("neo-tree.ui.popups")
  local popup_options = popups.popup_options
  popups.popup_options = function(title, ...)
    if title == "Neotree Help" then title = "NeoTree Shortcuts" end
    return popup_options(T(title), ...)
  end
  require("neo-tree.sources.common.help").show = require("config.navigation.neo_tree_help").show

  local components = require("neo-tree.sources.common.components")
  for _, name in ipairs({ "file_size", "last_modified", "created", "type", "filtered_by" }) do
    local render = components[name]
    if render then
      components[name] = function(config, node, state)
        local result = render(config, node, state)
        if type(result) == "table" and type(result.text) == "string" then
          if name == "filtered_by" then
            result.text = T(result.text)
          elseif node:get_depth() == 1 then
            -- Header has padding and a sort icon. Translate only the header token.
            for _, label in ipairs({ "Last Modified", "Created", "Size", "Type" }) do
              if result.text:find(label, 1, true) then
                result.text = result.text:gsub(label, function() return T(label) end, 1)
                break
              end
            end
          elseif name == "type" then
            result.text = T(result.text)
          end
        end
        return result
      end
    end
  end
end
return M
