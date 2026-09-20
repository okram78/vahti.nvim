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

When updates are found, vahti lists the affected plugins in a notification.
Review and apply updates with Neovim's own mechanism:

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
