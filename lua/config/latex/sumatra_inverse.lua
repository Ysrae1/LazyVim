-- Minimal Sumatra inverse-search RPC client. Started with -u NONE: no plugins,
-- second editor UI, Python environment, shell, or shared server registry.
local server, file, line, column = unpack(arg)
local ok, connected = pcall(vim.fn.sockconnect, 'pipe', server, { rpc = true })
if not ok or connected <= 0 then vim.cmd('cquit 1') end
local returned, result = pcall(vim.rpcrequest, connected, 'nvim_exec_lua',
  "return require('config.latex.sumatra').inverse(...)", { file, tonumber(line), tonumber(column) or 1 })
pcall(vim.fn.chanclose, connected)
if not returned or not result then vim.cmd('cquit 1') end
vim.cmd('qa!')
