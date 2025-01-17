return {
  "lervag/vimtex",
  lazy = false,
  -- ft = { "tex", "plaintex", "latex" }, -- 只在编辑tex文件时加载
  init = function()
    ------------------------------------------------------------------------------
    -- (1) 编译器设置：使用 latexmk，并以 xelatex/pdflatex 编译
    ------------------------------------------------------------------------------
    -- 让 vimtex 用 latexmk 作为后台编译器
    vim.g.vimtex_compiler_method = "latexmk"
    -- 配置 latexmk 的一些参数。例如，这里使用 xelatex（对应 VSCode 的 "xelatex" 配方）
    vim.g.vimtex_compiler_latexmk = {
      exe = "latexmk",
      build_dir = "",
      options = {
        -- 如果你希望始终使用 xelatex：
        "-xelatex",
        -- 如果改用 pdflatex，就写 "-pdf" 即可
        "-synctex=1",
        "-interaction=nonstopmode",
        "-file-line-error",
      },
    }

    ------------------------------------------------------------------------------
    -- (2) PDF 查看器：使用 Skim + SyncTeX
    ------------------------------------------------------------------------------
    -- 指定 vimtex 的查看器是 skim
    vim.g.vimtex_view_method = "skim"

    -- 配置 skim 的可执行文件和参数
    -- 以支持与 Vim 之间的同步(正向/反向搜索)
    vim.g.vimtex_view_skim_activate = 0
    vim.g.vimtex_view_skim_sync = 1
    vim.g.vimtex_view_skim_reading_bar = 1
    vim.g.vimtex_view_skim_no_select = 0

    vim.g.vimtex_view_skim = {
      -- 路径就是 VSCode 里 latex-workshop 用的 Skim 命令
      exe = "/Applications/Skim.app/Contents/SharedSupport/displayline",
      args = { "%line", "%pdf", "%tex" },
      -- 这里可再加 '-r', '-b' 等等，按你的需求
    }

    ------------------------------------------------------------------------------
    -- (3) 其他可选设置
    ------------------------------------------------------------------------------
    -- 不要自动编译，可手动执行 \ll 来编译
    -- 也可以: let g:vimtex_compiler_latexmk = { ... on_save = 1 } 以保存自动编译
    vim.g.vimtex_compiler_latexmk_engines = {
      _ = "-xelatex", -- 默认使用 xelatex
      pdflatex = "-pdf", -- 如果想在同一工程中切换
      lualatex = "-lualatex",
    }

    vim.g.vimtex_quickfix_ignore_filters = {
      "Underfull",
      "Overfull",
    }

    vim.api.nvim_set_keymap(
      "n",
      "<Leader>temp",
      ":read /Users/ysrae1/Documents/LaTeX Docs/templates/template_assignment.tex<CR>",
      { noremap = true, silent = true, desc = "LaTeX Template Assignment" }
    )

    --   在 lua/plugins/vimtex.lua 中
    --   vim.keymap.set(
    --     "n",
    --     "<Leader>temp",
    --     ':read "/Users/ysrae1/Documents/LaTeX Docs/templates/template_assignment.tex"<CR>',
    --     { noremap = true, silent = true }
    --   )
    --
    --   -- 如果需要 bibtex/biber，latexmk 会自动检测 `.bib` 变化并调用，无需手动写 recipes
  end,
}
