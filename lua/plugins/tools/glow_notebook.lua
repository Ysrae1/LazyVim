local runtime = require("config.media.runtime")

return {
  {
    "benlubas/molten-nvim",
    commit = runtime.molten_commit,
    pin = true,
    lazy = false,
    init = function()
      runtime.configure_molten()
    end,
    build = function()
      runtime.prepare_host()
      vim.cmd("UpdateRemotePlugins")
    end,
  },
  {
    "GCBallesteros/jupytext.nvim",
    commit = runtime.jupytext_commit,
    pin = true,
    lazy = false,
    config = function()
      runtime.configure_jupytext()
    end,
  },
}
