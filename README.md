# vahti.nvim

vahti.nvim watches plugins managed by Neovim 0.12's built-in `vim.pack`.
It checks for updates after startup and tells you to use Neovim's own
`:packupdate` command. vahti.nvim never updates plugins automatically.

## Requirements

- Neovim 0.12 or newer
- Plugins installed with `vim.pack.add()`

## Setup

Add vahti.nvim with `vim.pack.add()` and configure it in `init.lua`:

```lua
vim.pack.add({ "https://github.com/okram78/vahti.nvim" })

require("vahti").setup({
  startup_delay = 3000,
  check_interval = 24 * 60 * 60,
})
```

By default, vahti waits three seconds after `VimEnter` and checks at most once
per day. The last successful check is stored in Neovim's state directory. A
weekly check can be configured like this:

```lua
require("vahti").setup({
  check_interval = 7 * 24 * 60 * 60,
})
```

To check immediately, run `:VahtiCheck`. When updates are found, run
`:packupdate` to review and apply them.
