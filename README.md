# vahti.nvim

vahti.nvim watches plugins managed by Neovim 0.12's built-in `vim.pack`.
It checks for updates in the background and displays a notification when they
are available. vahti.nvim never updates plugins automatically.

## Requirements

- Neovim 0.12 or newer
- Plugins installed with `vim.pack.add()`
- Git available on `PATH`

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

To check on every startup instead, set `check_interval = 0`:

```lua
require("vahti").setup({
  startup_delay = 3000,
  check_interval = 0,
})
```

When updates are found, vahti displays a notification with the plugin names.
To review and apply updates, run Neovim's own mechanism:

```vim
:lua vim.pack.update()
```

This opens Neovim's review buffer. Use `:write` in that buffer to apply the
selected updates, or `:quit` to cancel them. The background check uses Git to
inspect remote revisions and does not modify plugin files.

To check immediately, run `:VahtiCheck`.

## Tests

Run the local headless test suite from the repository root:

```sh
NVIM_APPNAME=vahti-test nvim --headless -u tests/minimal_init.lua -l tests/vahti_spec.lua
```

The tests mock Git and `vim.pack`, so they do not update installed plugins or
require a network connection.

## Development

Changes are developed on `development` and merged into `main` through pull
requests. GitVersion reads semver directives from commit messages:

```text
feat: add a new check mode +semver: minor
fix: handle missing Git +semver: patch
```

The first `0.1.0` release is created from `main` after the release pull
request has passed CI. Push a `vX.Y.Z` tag to start the release workflow.
