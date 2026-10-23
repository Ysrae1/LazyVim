local windows = vim.fn.has("win32") == 1
local codex_env = { HOME = vim.env.HOME, PATH = vim.env.PATH }
if windows then
  -- ACP passes an explicit environment to uv.spawn. Preserve Windows runtime
  -- paths while keeping API keys out of this ChatGPT-authenticated child.
  codex_env = vim.fn.environ()
  for name in pairs(codex_env) do
    if name:upper() == "OPENAI_API_KEY" or name:upper() == "CODEX_API_KEY" then codex_env[name] = nil end
  end
  codex_env.HOME = codex_env.HOME or vim.env.USERPROFILE
end
local windows_node = windows and vim.fn.exepath("node") or nil
if windows and windows_node == "" then
  local private_node = vim.fn.stdpath("data") .. "/mason/.glow-runtime/runtime/node/node.exe"
  if vim.fn.filereadable(private_node) == 1 then
    windows_node = private_node
    -- Only this ACP child receives the verified private Node directory.
    codex_env.PATH = vim.fn.fnamemodify(private_node, ":h") .. ";" .. (codex_env.PATH or "")
  end
end
local adapter = vim.fn.stdpath("data") .. "/codex-acp/node_modules/@agentclientprotocol/codex-acp/dist/index.js"

return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false, -- set this if you want to always pull the latest change
    opts = {
      provider = "codex",
      acp_providers = {
        codex = {
          -- Use the maintained adapter with the existing ChatGPT login.
          -- Remove API keys only for this process; DeepSeek stays configured below.
          command = windows and (windows_node ~= "" and windows_node or "node") or "/usr/bin/env",
          args = windows and { adapter } or {
            "-u", "OPENAI_API_KEY",
            "-u", "CODEX_API_KEY",
            "/opt/homebrew/bin/node",
            adapter,
          },
          env = codex_env,
        },
      },
      selection = {
        hint_display = "none",
      },
      providers = {
      openai = {
        endpoint = "https://api.deepseek.com/v1",
        model = "deepseek-chat",
        extra_request_body = {
        temperature = 0,
        max_tokens = 4096,
        -- optional
        },
        timeout = 30000, -- Timeout in milliseconds

        api_key_name = "OPENAI_API_KEY", -- default OPENAI_API_KEY if not set
      }
      },
    },
    config = function(_, opts)
      local client = require("avante.libs.acp_client")
      if not client._codex_auth_status_handler then
        local handle_notification = client._handle_notification
        function client:_handle_notification(message_id, method, params)
          -- New Codex adapters push login status through this ACP extension.
          if method == "_auth/status_update" then
            self.auth_status = params
            return
          end
          return handle_notification(self, message_id, method, params)
        end
        client._codex_auth_status_handler = true
      end
      require("avante").setup(opts)
      -- ACP authenticates through Codex. This Avante version's input box
      -- otherwise waits for the traditional API-key login flag.
      if opts.acp_providers and opts.acp_providers[opts.provider] then
        vim.g.avante_login = true
      end
    end,
    -- The PowerShell host can have a different architecture from Neovim.
    -- Build the locked source explicitly for this Neovim's LuaJIT ABI.
    build = windows and function(plugin)
      local architecture = ({ arm64 = "arm64", x64 = "x64" })[jit.arch]
      assert(architecture, "Avante: unsupported Windows Neovim architecture: " .. jit.arch)
      local helper = vim.fn.stdpath("config") .. "/lua/config/platform/avante_build.ps1"
      assert(vim.fn.filereadable(helper) == 1, "Avante native build helper is missing: " .. helper)
      local process = vim.system({
        "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper,
        "-Source", plugin.dir, "-Architecture", architecture,
        "-BuildDirectory", vim.fn.stdpath("cache") .. "/native-plugins/avante/" .. architecture,
      }, { text = true }):wait(2760000)
      if process.code ~= 0 then error("Avante native build failed: " .. (process.stderr or process.stdout or "unknown error")) end
    end or "make",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      --- The below dependencies are optional,
      "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
      "zbirenbaum/copilot.lua", -- for providers='copilot'
      {
        -- support for image pasting
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          -- recommended settings
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            -- required for Windows users
            use_absolute_path = true,
          },
        },
      },
      {
        -- Make sure to set this up properly if you have lazy=true
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          file_types = { "markdown", "Avante" },
          latex = {
            converter = vim.env.GLOW_LATEX2TEXT or (vim.fn.stdpath("data") .. "/latex2text-venv/"
              .. (windows and "Scripts/latex2text.exe" or "bin/latex2text")),
          },
        },
        ft = { "markdown", "Avante" },
      },
    },
  },
}
