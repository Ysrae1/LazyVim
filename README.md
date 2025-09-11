# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

---

## My Own Configuration

This is my personal Neovim/Neovide configuration using the LazyVim framework, with the theme/UI framework borrowed from NvChad. I’ve mapped some conventional key functions for macOS, including many text editing operations using 󰘳 across almost all 5 modes. So, this setup is a highly personalized development environment.

Currently, there are still many comments in Chinese that need to be optimized (or maybe they won’t?).

## Installation

Simply run the following command to install:

```sh
git clone git@github.com:Ysrae1/base46.git ~/.config/nvim
```

For the complete instructions, please refer to the original [LazyVim](https://github.com/LazyVim/LazyVim) repository for detailed steps.

## Other Dependencies

Apart from the packages maintained by LazyVim, the [unimatrix](https://github.com/will8211/unimatrix) is needed for the startup visual of [neovide](https://neovide.dev) and the [snacks](https://github.com/folke/snacks.nvim) dashboard. The base46 version should be chosen from my repository due to the dependencied of the binary color theme files for _neo-tree_.

## Neovide Users

As for neovide users, the `Fira Code Nerd Font Mono` font is specified in `./lua/neovide.lua`, which can be easily found [here](https://www.nerdfonts.com/font-downloads).

## Extra

The button and the corresponding function at the upper right angle of the window can be easily removed/replaces/modified by editing the `./lua/chadrc.lua`.

## Note

The directory/file structure may appear chaotic and rough, but this is likely to persist for quite some time 😅.
