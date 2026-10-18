return {
  settings = {
    texlab = {
      build = {
        executable = "latexmk",
        args = {
          "-xelatex",
          "-file-line-error",
          "-interaction=nonstopmode",
          "-synctex=1",
          "%f",
        },
        forwardSearchAfter = false,
        onSave = true,
      },
      forwardSearch = {
        executable = "/Applications/Skim.app/Contents/SharedSupport/displayline",
        args = { "%l", "%p", "%f" },
      },
      chktex = {
        onEdit = true,
        onOpenAndSave = true,
      },
      bibtexFormatter = "texlab",
    },
  },
}
