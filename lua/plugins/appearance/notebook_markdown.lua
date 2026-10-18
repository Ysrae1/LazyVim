return {
  'MeanderingProgrammer/render-markdown.nvim',
  opts = function(_, options)
    return require('config.media.notebook_markdown').options(options)
  end,
}
