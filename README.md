# vahti.nvim

vahti.nvim watches plugins managed by Neovim 0.12's built-in `vim.pack`.
It automatically checks for updates in the background and displays a
notification when they are available. You can also check manually with
`:VahtiCheck`. vahti.nvim never updates plugins automatically.

![vahti.nvim reporting that no plugin updates are available](docs/assets/vahti-check.gif)

Read the [full documentation](https://okram78.github.io/vahti.nvim/).

## Requirements

- Neovim 0.12 or newer
- Plugins installed with `vim.pack.add()`
- Git available on `PATH`

If a plugin spec has a `version`, vahti treats it as a literal Git ref (for
example, a tag such as `v1.2.3`), not as a semver constraint.

## Setup

Add vahti.nvim with `vim.pack.add()` and configure it in `init.lua`:

```lua
vim.pack.add({ "https://github.com/okram78/vahti.nvim" })

require("vahti").setup({
  startup_delay = 3000,
  check_interval = 24 * 60 * 60,
  git_timeout = 10000,
})
```

By default, vahti waits three seconds after `VimEnter` and checks at most once
per day. Each Git check is terminated after 10 seconds by default. The last
successful check is stored in Neovim's state directory. A weekly check can be
configured like this:

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

Automatic and manual checks only notify when updates are available. Telescope
opens on demand with `:VahtiUpdate` or the default `<leader>pu` mapping. Use
`<Tab>` to select or deselect plugins and `<CR>` to apply the selection. The
preview shows the source, current/target revisions, and pending commits. Commit
details are fetched when a plugin is previewed. Selected updates are applied
immediately without opening Neovim's confirmation buffer. Telescope is optional
and needed only for the Telescope picker.

The mapping is configurable or can be disabled:

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

Notification templates support `{count}` and `{plugins}`. The Telescope
template also supports `{keymap}` and `{review_hint}`.

You can also review and apply updates with Neovim's own mechanism:

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

Run the tests locally:

```sh
NVIM_APPNAME=vahti-test nvim --headless -u tests/minimal_init.lua -l tests/vahti_spec.lua
```

Merging to `main` creates a version tag and GitHub release automatically.
Use `+semver: minor` or `+semver: patch` in a commit message when needed.
