local vahti = require("vahti")

local original_get = vim.pack.get
local original_update = vim.pack.update
local original_system = vim.system
local original_notify = vim.notify
local passed = 0
local failed = 0

local function assert_contains(value, expected)
  assert(value:find(expected, 1, true), string.format("Expected %q to contain %q", value, expected))
end

local function replace_field(table, field, value)
  rawset(table, field, value)
end

local function run_test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. "\n" .. err)
  end
end

local function check_with(remote_revision, current_revision, exit_code, version)
  local notifications = {}
  local finished = false

  replace_field(vim, "notify", function(message, level)
    notifications[#notifications + 1] = { message = message, level = level }
  end)
  replace_field(vim.pack, "get", function()
    return {
      {
        rev = current_revision,
        spec = {
          name = "example-plugin",
          src = "https://example.invalid/example-plugin",
          version = version,
        },
      },
    }
  end)
  replace_field(vim, "system", function(_, opts, callback)
    assert(opts.timeout == 10000)
    vim.schedule(function()
      callback({
        code = exit_code or 0,
        stdout = remote_revision .. "\tHEAD\n",
      })
      finished = true
    end)
  end)

  assert(vahti.check(true))
  vim.wait(1000, function()
    return finished
  end, 10)

  return notifications
end

vahti.setup({ startup_delay = 0, check_interval = 0 })

run_test("registers VahtiCheck", function()
  assert(vim.fn.exists(":VahtiCheck") == 2)
end)

run_test("registers VahtiUpdate", function()
  assert(vim.fn.exists(":VahtiUpdate") == 2)
end)

run_test("notifies about remote updates", function()
  local notifications = check_with("abcdef1234567890", "0123456789abcdef")
  assert(#notifications == 1)
  assert_contains(notifications[1].message, "Plugin updates available (1)")
  assert_contains(notifications[1].message, "Use :lua vim.pack.update()")
  assert(notifications[1].message:find(":VahtiUpdate", 1, true) == nil)
  assert(notifications[1].message:find("<leader>pu", 1, true) == nil)
end)

run_test("VahtiUpdate applies only plugins selected in Telescope", function()
  local original_modules = {
    actions = package.loaded["telescope.actions"],
    action_state = package.loaded["telescope.actions.state"],
    finders = package.loaded["telescope.finders"],
    pickers = package.loaded["telescope.pickers"],
    previewers = package.loaded["telescope.previewers"],
    sorters = package.loaded["telescope.sorters"],
  }
  local original_notify = vim.notify
  local original_get = vim.pack.get
  local original_system = vim.system
  local notifications = {}
  local picker_options
  local choose_updates
  local completion_callback
  local select_all_prompt
  local select_all_calls = 0
  local updated_names
  local update_options

  local function restore()
    package.loaded["telescope.actions"] = original_modules.actions
    package.loaded["telescope.actions.state"] = original_modules.action_state
    package.loaded["telescope.finders"] = original_modules.finders
    package.loaded["telescope.pickers"] = original_modules.pickers
    package.loaded["telescope.previewers"] = original_modules.previewers
    package.loaded["telescope.sorters"] = original_modules.sorters
    replace_field(vim, "notify", original_notify)
    replace_field(vim.pack, "get", original_get)
    replace_field(vim, "system", original_system)
    replace_field(vim.pack, "update", original_update)
    vahti.setup({})
  end

  package.loaded["telescope.actions"] = {
    select_default = { replace = function(_, action) choose_updates = action end },
    close = function() end,
    select_all = function(prompt_bufnr)
      select_all_prompt = prompt_bufnr
      select_all_calls = select_all_calls + 1
    end,
  }
  package.loaded["telescope.actions.state"] = {
    get_current_picker = function()
      return {
        get_multi_selection = function()
          return { { value = { name = "example-plugin" } } }
        end,
      }
    end,
    get_selected_entry = function()
      return nil
    end,
  }
  package.loaded["telescope.finders"] = {
    new_table = function(opts)
      return opts
    end,
  }
  package.loaded["telescope.pickers"] = {
    new = function(_, opts)
      picker_options = opts
      return {
        find = function() end,
        register_completion_callback = function(_, callback)
          completion_callback = callback
        end,
      }
    end,
  }
  package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function(opts)
      return opts
    end,
  }
  package.loaded["telescope.sorters"] = {
    get_generic_fuzzy_sorter = function()
      return {}
    end,
  }
  local notification_count = 0
  replace_field(vim, "notify", function(message)
    notification_count = notification_count + 1
    notifications[#notifications + 1] = message
  end)
  replace_field(vim.pack, "get", function()
    return {
      {
        rev = "0123456789abcdef",
        path = "/plugins/example-plugin",
        spec = { name = "example-plugin", src = "https://example.invalid/example-plugin" },
      },
    }
  end)
  replace_field(vim, "system", function(_, _, callback)
    vim.schedule(function()
      callback({ code = 0, stdout = "abcdef1234567890\tHEAD\n" })
    end)
  end)
  replace_field(vim.pack, "update", function(names, opts)
    updated_names = names
    update_options = opts
  end)

  local ok, err = xpcall(function()
    local check_finished = false
    assert(vahti.check(true, function()
      check_finished = true
    end))
    vim.wait(1000, function()
      return check_finished
    end, 10)

    vim.cmd("VahtiUpdate")
    assert(picker_options)
    assert(picker_options.prompt_title:find("<Tab>", 1, true))
    assert(picker_options.results_title == "Plugin updates")
    assert(picker_options.preview_title == "Pending update details")
    assert(picker_options.previewer)
    assert(picker_options.layout_config.preview_width > 0)
    assert(picker_options.layout_config.width(nil, 300, 100) == 150)
    assert(picker_options.layout_config.height(nil, 300, 100) == 40)
    assert(not completion_callback, "updates should not be preselected by default")

    local update = picker_options.finder.results[1]
    update.details = "> abcdef0 │ Add example feature"
    local preview_buf = vim.api.nvim_create_buf(false, true)
    picker_options.previewer.define_preview({ state = { bufnr = preview_buf } }, { value = update })
    local preview = table.concat(vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false), "\n")
    assert_contains(preview, "Path:            /plugins/example-plugin")
    assert_contains(preview, "Source:          https://example.invalid/example-plugin")
    assert_contains(preview, "Pending updates:")
    assert_contains(preview, "Add example feature")
    local preview_ns = vim.api.nvim_get_namespaces()["vahti-telescope-preview"]
    local highlights = vim.api.nvim_buf_get_extmarks(preview_buf, preview_ns, 0, -1, { details = true })
    assert(#highlights > 0, "preview should apply syntax highlights")
    vim.api.nvim_buf_delete(preview_buf, { force = true })

    picker_options.attach_mappings(1)
    choose_updates()
    assert(vim.deep_equal(updated_names, { "example-plugin" }))
    assert(update_options.force == true)

    picker_options = nil
    choose_updates = nil
    local previous_notifications = notification_count
    assert(vahti.check(true))
    vim.wait(1000, function()
      return notification_count > previous_notifications
    end, 10)
    assert(picker_options == nil, "automatic checks should not open Telescope")
    assert_contains(notifications[#notifications], "<leader>pu")

    vahti.setup({ telescope = { select_all_by_default = true } })
    local keymap
    local update_lhs = (vim.g.mapleader or "\\") .. "pu"
    for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
      if mapping.lhs == update_lhs then
        keymap = mapping
        break
      end
    end
    assert(keymap and keymap.callback)
    keymap.callback()
    assert(picker_options, "the configured keymap should open cached updates")
    assert(completion_callback, "the selection callback should be registered")
    completion_callback({ prompt_bufnr = 42 })
    completion_callback({ prompt_bufnr = 42 })
    assert(select_all_prompt == 42)
    assert(select_all_calls == 1, "the default selection should be initialized only once")
  end, debug.traceback)

  restore()
  assert(ok, err)
end)

run_test("works without Telescope and allows custom fallback messages", function()
  local previous_picker = package.loaded["telescope.pickers"]
  local previous_preload = package.preload["telescope.pickers"]
  local original_notify = vim.notify

  local function restore()
    package.loaded["telescope.pickers"] = previous_picker
    package.preload["telescope.pickers"] = previous_preload
    replace_field(vim, "notify", original_notify)
    vahti.setup({})
  end

  package.loaded["telescope.pickers"] = nil
  package.preload["telescope.pickers"] = function()
    error("Telescope is unavailable")
  end

  local ok, err = xpcall(function()
    vahti.setup({})
    local notifications = check_with("abcdef1234567890", "0123456789abcdef")
    assert(#notifications == 1)
    assert_contains(notifications[1].message, "Use :lua vim.pack.update()")
    assert(notifications[1].message:find("VahtiUpdate", 1, true) == nil)
    assert(notifications[1].message:find("<leader>pu", 1, true) == nil)

    vahti.setup({
      messages = {
        updates_without_telescope = "Available: {count}; {plugins}",
      },
    })
    local custom_notifications = check_with("abcdef1234567890", "0123456789abcdef")
    assert(custom_notifications[1].message == "Available: 1; example-plugin")

    local opened_picker = vahti.update()
    assert(not opened_picker)
    assert_contains(custom_notifications[#custom_notifications].message, "Telescope.nvim is required")
  end, debug.traceback)

  restore()
  assert(ok, err)
end)

run_test("fetches pending commit details on demand", function()
  local git = require("vahti.git")
  local original_system = vim.system
  local commands = {}
  local details
  local detail_error

  replace_field(vim, "system", function(command, opts, callback)
    commands[#commands + 1] = { command = command, opts = opts }
    vim.schedule(function()
      local stdout = command[2] == "log" and command[5] == "--right-only"
          and "> abcdef0 │ Add remote feature"
        or ""
      callback({ code = 0, stdout = stdout, stderr = "" })
    end)
  end)

  local ok, err = xpcall(function()
    git.get_update_details({
      name = "example-plugin",
      path = "/plugins/example-plugin",
      src = "https://example.invalid/example-plugin",
      rev_before = "0123456789abcdef",
      rev_after = "abcdef1234567890",
      remote_ref = "refs/heads/main",
    }, 10000, function(result, failure)
      details = result
      detail_error = failure
    end)

    vim.wait(1000, function()
      return details ~= nil
    end, 10)
    assert(not detail_error, detail_error)
    assert_contains(details, "Add remote feature")
    assert(#commands == 3)
    assert(commands[1].command[2] == "fetch")
    assert(commands[1].opts.cwd == "/plugins/example-plugin")
    assert(commands[2].command[2] == "log")
    assert(commands[3].command[2] == "log")
  end, debug.traceback)

  replace_field(vim, "system", original_system)
  assert(ok, err)
end)

run_test("reports when no updates are available", function()
  local notifications = check_with("abcdef1234567890", "abcdef1234567890")
  assert(#notifications == 1)
  assert_contains(notifications[1].message, "No plugin updates available.")
end)

run_test("uses the highest matching remote tag for a version range", function()
  local notifications = {}
  local finished = false

  replace_field(vim, "notify", function(message, level)
    notifications[#notifications + 1] = { message = message, level = level }
  end)
  replace_field(vim.pack, "get", function()
    return {
      {
        rev = "78336bc89ee5365633bcf754d93df01678b5c08f",
        spec = {
          name = "example-plugin",
          src = "https://example.invalid/example-plugin",
          version = vim.version.range("1"),
        },
      },
    }
  end)
  replace_field(vim, "system", function(command, opts, callback)
    assert(opts.timeout == 10000)
    assert(command[1] == "git")
    assert(command[2] == "ls-remote")
    assert(command[3] == "--tags")
    vim.schedule(function()
      callback({
        code = 0,
        stdout = table.concat({
          "efcf2d949592d4a075c038355c8e6653d2dab4a3\trefs/tags/v1.10.1",
          "451168851e8e2466bc97ee3e026c3dcb9141ce07\trefs/tags/v1.10.1^{}",
          "9b189bb2a0e03412e0e901dfbd09904f86cd593c\trefs/tags/v1.10.2",
          "78336bc89ee5365633bcf754d93df01678b5c08f\trefs/tags/v1.10.2^{}",
          "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\trefs/tags/v2.0.0",
          "", -- Keep the command output newline-terminated.
        }, "\n"),
      })
      finished = true
    end)
  end)

  assert(vahti.check(true))
  vim.wait(1000, function()
    return finished
  end, 10)

  assert(#notifications == 1)
  assert_contains(notifications[1].message, "No plugin updates available.")
end)

run_test("warns when Git check fails", function()
  local notifications = check_with("abcdef1234567890", "0123456789abcdef", 1)
  assert(#notifications == 1)
  assert_contains(notifications[1].message, "Could not check:")
end)

run_test("reports successful and failed checks together", function()
  local notifications = {}
  local finished = 0

  replace_field(vim, "notify", function(message, level)
    notifications[#notifications + 1] = { message = message, level = level }
  end)
  replace_field(vim.pack, "get", function()
    return {
      {
        rev = "0123456789abcdef",
        spec = { name = "updated-plugin", src = "https://example.invalid/updated-plugin" },
      },
      {
        rev = "0123456789abcdef",
        spec = { name = "unreachable-plugin", src = "https://example.invalid/unreachable-plugin" },
      },
    }
  end)
  replace_field(vim, "system", function(command, opts, callback)
    assert(opts.timeout == 10000)
    vim.schedule(function()
      local is_failure = command[3]:find("unreachable-plugin", 1, true) ~= nil
      callback({
        code = is_failure and 1 or 0,
        stdout = "abcdef1234567890\tHEAD\n",
      })
      finished = finished + 1
    end)
  end)

  assert(vahti.check(true))
  vim.wait(1000, function()
    return finished == 2
  end, 10)

  assert(#notifications == 1)
  assert_contains(notifications[1].message, "Plugin updates available (1): updated-plugin")
  assert_contains(notifications[1].message, "Could not check: unreachable-plugin")
end)

replace_field(vim.pack, "get", original_get)
replace_field(vim.pack, "update", original_update)
replace_field(vim, "system", original_system)
replace_field(vim, "notify", original_notify)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
  vim.cmd("cquit 1")
end
