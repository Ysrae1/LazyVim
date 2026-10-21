-- Presentation-only Notebook chrome. Molten chunks/Notebook data stay unchanged.
local M = {}
local api = vim.api
local records, popups, configured = {}, {}, false
local popup_ns = api.nvim_create_namespace("glow.notebook.chrome")
local function locale() return require("config.platform.locale") end
local function text(lines)
  local values = {}
  for _, chunk in ipairs(lines or {}) do values[#values + 1] = chunk[1] end
  return table.concat(values)
end
local function header(lines)
  for _, chunk in ipairs((lines or {})[1] or {}) do
    if chunk[2] == "GlowNotebookOutputNumber" and chunk[1]:match("^Out%[[^%]]*%]:$") then return true end
  end
  return false
end
local function key(buf, ns, id) return buf .. ":" .. ns .. ":" .. id end

function M.render(lines, metadata)
  local rendered = vim.deepcopy(lines)
  if locale().current() ~= "zh" or not header(lines) then return rendered end
  for _, chunk in ipairs(rendered[1]) do
    -- These are separate semantic chunks emitted by our pinned provider adapter.
    -- Never search or replace status words inside a user's printed output.
    if chunk[2] == "MoltenVirtualText" and chunk[1] == "[OLD] " then
      chunk[1] = locale().t("[OLD]") .. " "
    elseif chunk[2] == "GlowNotebookOutputSuccess" and chunk[1] == "✓ Done" then
      chunk[1] = "✓ " .. locale().t("Done")
    elseif chunk[2] == "GlowNotebookOutputFailure" and chunk[1] == "✗ Failed" then
      chunk[1] = "✗ " .. locale().t("Failed")
    elseif metadata and chunk[2] == "GlowNotebookOutputRunning" and chunk[1] == "... Running" then
      chunk[1] = "... " .. locale().t("Running")
    elseif metadata and chunk[2] == "GlowNotebookOutputPending" then
      if chunk[1] == "* On Hold" then chunk[1] = "* " .. locale().t("On Hold")
      elseif chunk[1] == "Never Run" then chunk[1] = locale().t("Never Run") end
    end
  end
  -- Only the provider can identify an actually generated truncation row. An
  -- old host's unmarked lookalike is deliberately left intact, even at the end.
  -- Running/pending labels also remain canonical in that legacy case, because
  -- its already-loaded Notebook controls parse those labels for safety.
  local row = metadata and metadata.fold_row
  if row and rendered[row] then
    local arrow, count, trailing = text(lines[row]):match("^(.-) ([1-9]%d*) More lines(%s*)$")
    if arrow == "󰁅" or arrow == "↑" then
      rendered[row] = { { arrow .. " " .. locale().t("%d More lines"):format(tonumber(count)) .. trailing,
        lines[row][1][2] } }
    end
  end
  return rendered
end

function M.status(lines)
  local first = ""
  for _, chunks in ipairs(lines or {}) do
    first = text(chunks)
    if not first:match("^%s*$") then break end
  end
  local status = first:match("^Out%[[^%]]*%]: (.*)$") or first:match("^%[OLD%] Out%[[^%]]*%]: (.*)$")
  if not status then return end
  if status:sub(1, 11) == "... Running" then return "running" end
  if status:sub(1, 9) == "* On Hold" then return "pending" end
end

function M.canonical_lines(buf, ns, id, lines)
  if not ns or not id then return lines end
  local record = records[key(buf, ns, id)]
  return record and vim.deep_equal(record.rendered, lines) and record.lines or lines
end

function M.write(buf, ns, row, col, options, images, owner, metadata)
  M.setup()
  local canonical = vim.deepcopy(options.virt_lines)
  options = vim.deepcopy(options)
  options.virt_lines = M.render(canonical, metadata)
  local bridge = package.loaded["config.media.molten_images"]
  local id
  if images and #images > 0 and bridge and bridge.set_inline_output then
    id = bridge.set_inline_output(buf, ns, row, col, options, images, owner)
  else
    id = api.nvim_buf_set_extmark(buf, ns, row, col, options)
  end
  records[key(buf, ns, id)] = { lines = canonical, rendered = vim.deepcopy(options.virt_lines), metadata = metadata }
  return id
end

-- Molten's nofile viewer stores its generated header as the first line. Only
-- that line is UI; all remaining output/trace lines stay byte-for-byte intact.
function M.refresh_popups()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "molten_output" and vim.bo[buf].buftype == "nofile" then
      local current = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
      local record = popups[buf]
      local canonical = record and current == record.rendered and record.canonical or current
      local old, number, space, rest = canonical:match("^(%[OLD%] )(Out%[[^%]]*%]:)( ?)(.*)$")
      if not number then number, space, rest = canonical:match("^(Out%[[^%]]*%]:)( ?)(.*)$") end
      if number then
        local chunks = {}
        if old then chunks[#chunks + 1] = { old, "MoltenVirtualText" } end
        chunks[#chunks + 1] = { number, "GlowNotebookOutputNumber" }
        chunks[#chunks + 1] = { space, "MoltenVirtualText" }
        local matched = false
        for _, pair in ipairs({ {"✓ Done", "Success"}, {"✗ Failed", "Failure"},
          {"... Running", "Running"}, {"* On Hold", "Pending"}, {"Never Run", "Pending"} }) do
          if rest:sub(1, #pair[1]) == pair[1] then
            chunks[#chunks + 1] = { pair[1], "GlowNotebookOutput" .. pair[2] }
            chunks[#chunks + 1] = { rest:sub(#pair[1] + 1), "MoltenVirtualText" }
            matched = true; break
          end
        end
        if not matched then chunks[#chunks + 1] = { rest, "MoltenVirtualText" } end
        chunks = M.render({ chunks }, {})[1]
        local rendered = text(chunks)
        if not record or current ~= rendered or not vim.deep_equal(record.chunks, chunks) then
          if current ~= rendered then
            local modifiable, readonly = vim.bo[buf].modifiable, vim.bo[buf].readonly
            vim.bo[buf].modifiable, vim.bo[buf].readonly = true, false
            local ok, err = pcall(api.nvim_buf_set_lines, buf, 0, 1, false, { rendered })
            vim.bo[buf].modifiable, vim.bo[buf].readonly = modifiable, readonly
            if not ok then error(err) end
          end
          api.nvim_buf_clear_namespace(buf, popup_ns, 0, 1)
          local col = 0
          for _, chunk in ipairs(chunks) do
            if #chunk[1] > 0 then api.nvim_buf_set_extmark(buf, popup_ns, 0, col,
              { end_col = col + #chunk[1], hl_group = chunk[2], priority = 220 }) end
            col = col + #chunk[1]
          end
          popups[buf] = { canonical = canonical, rendered = rendered, chunks = chunks }
        end
      end
    else popups[buf] = nil end
  end
end

function M.refresh()
  local ns = api.nvim_get_namespaces()["molten-extmarks"]
  if not ns then M.refresh_popups(); return end
  local seen = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) then
      for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        local details, id = mark[4], key(buf, ns, mark[1])
        local lines = details.virt_lines
        if lines and not details.invalid then
          seen[id] = true
          local record = records[id]
          if not record or not vim.deep_equal(lines, record.rendered) then
            -- Safe adoption of already-running hosts: only their semantic header
            -- is known. No footer is inferred from arbitrary user output text.
            record = header(lines) and { lines = vim.deepcopy(lines), rendered = lines } or nil
            records[id] = record
          end
          if record then
            local rendered = M.render(record.lines, record.metadata)
            if not vim.deep_equal(lines, rendered) then
              local opts = { id = mark[1], virt_lines = rendered }
              -- Keep geometry/placement and deletion gravity from the same mark.
              for _, name in ipairs({ "virt_lines_above", "virt_lines_leftcol", "virt_lines_overflow",
                "right_gravity", "end_right_gravity", "priority", "strict", "undo_restore", "invalidate" }) do
                if details[name] ~= nil then opts[name] = details[name] end
              end
              api.nvim_buf_set_extmark(buf, ns, mark[2], mark[3], opts)
            end
            record.rendered = vim.deepcopy(rendered)
          end
        end
      end
    end
  end
  for id in pairs(records) do if not seen[id] then records[id] = nil end end
  M.refresh_popups()
end

function M.setup()
  if not configured then
    configured = true
    local group = api.nvim_create_augroup("GlowNotebookChromeLocale", { clear = true })
    api.nvim_create_autocmd("User", { group = group, pattern = "GlowLanguageChanged", callback = M.refresh })
    api.nvim_create_autocmd("FileType", { group = group, pattern = "molten_output", callback = M.refresh_popups })
  end
  -- Reuse the existing presentation refresh in old live sessions. Its state,
  -- timer, images and kernel are retained; this adds no polling service.
  local ui = package.loaded["config.media.notebook_ui"]
  if ui and not ui._glow_chrome_refresh then
    local original = ui.refresh
    ui.refresh = function(...) M.refresh(); return original(...) end
    ui._glow_chrome_refresh = true
  end
end
return M
