---
layout: default
title: vahti.nvim
---

# vahti.nvim

Background update notifications for plugins managed by Neovim 0.12's built-in
`vim.pack`.

vahti.nvim checks remote Git revisions in the background and notifies you when
updates are available. It never updates plugin files automatically.

## Requirements

- Neovim 0.12 or newer
- Plugins installed with `vim.pack.add()`
- Git available on `PATH`

## Installation

Add vahti.nvim with `vim.pack.add()` and configure it in your `init.lua`:

```lua
vim.pack.add({ "https://github.com/okram78/vahti.nvim" })

require("vahti").setup({
  startup_delay = 3000,
  check_interval = 24 * 60 * 60,
  git_timeout = 10000,
})
```

By default, vahti waits three seconds after `VimEnter` and checks at most once
per day. The last successful check is stored in Neovim's state directory.

## Configuration

| Option | Default | Description |
| --- | ---: | --- |
| `startup_delay` | `3000` | Delay after `VimEnter`, in milliseconds. |
| `check_interval` | `86400` | Minimum time between automatic checks, in seconds. |
| `git_timeout` | `10000` | Maximum duration of one Git check, in milliseconds. |
| `update_keymap` | `"<leader>pu"` | Key to open cached updates in Telescope; `false` disables the mapping. |
| `telescope.max_width` | `150` | Maximum picker width, in columns. |
| `telescope.max_height` | `40` | Maximum picker height, in rows. |
| `telescope.select_all_by_default` | `false` | Preselect every available update in the picker. |
| `messages.updates_with_telescope` | See below | Notification template when Telescope is available. |
| `messages.updates_without_telescope` | See below | Notification template when Telescope is unavailable. |

For a weekly check:

```lua
require("vahti").setup({
  check_interval = 7 * 24 * 60 * 60,
})
```

To check on every startup, set `check_interval = 0`.

If a plugin spec has a `version`, vahti treats it as a literal Git ref, such as
`v1.2.3`, rather than as a semver constraint.

## Checking and updating

Run this command to check immediately:

```vim
:VahtiCheck
```

Automatic and manual checks only notify when updates are available. To inspect
the latest results in Telescope, use the default `<leader>pu` mapping or run:

```vim
:VahtiUpdate
```

The right-hand preview shows the path, source, current and target revisions, and
pending commits. Commit details are fetched when a plugin is previewed. Use
`<Tab>` to select or deselect plugins, then `<CR>` to apply the selection.
Selected plugins update immediately without Neovim's confirmation buffer.
Telescope is optional and only needed for the picker. If no check has found
updates yet, `:VahtiUpdate` starts a check first.

Change or disable the mapping in setup:

```lua
require("vahti").setup({
  update_keymap = "<leader>pu", -- or false to disable
  telescope = {
    max_width = 150,
    max_height = 40,
    select_all_by_default = true,
  },
  messages = {
    updates_with_telescope = "Updates ({count}): {plugins}. {review_hint}.",
    updates_without_telescope = "Updates ({count}): {plugins}.",
  },
})
```

Both templates accept `{count}` and `{plugins}`. The Telescope template also
accepts `{keymap}` and `{review_hint}`. When Telescope is unavailable, the
default notification instead points to `vim.pack.update()` and does not mention
`:VahtiUpdate` or the Telescope keymap.

Alternatively, review and apply updates with Neovim's own mechanism:

```vim
:lua vim.pack.update()
```

This opens Neovim's review buffer. Use `:write` to apply selected updates or
`:quit` to cancel them. The background check only inspects remote revisions;
it does not modify installed plugins.

## Development

Run the tests from the repository root:

```sh
NVIM_APPNAME=vahti-test nvim --headless -u tests/minimal_init.lua -l tests/vahti_spec.lua
```

The tests mock Git and `vim.pack`, so they do not require network access.

[View the source on GitHub](https://github.com/okram78/vahti.nvim)
