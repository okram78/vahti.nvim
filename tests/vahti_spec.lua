local vahti = require("vahti")

local original_get = vim.pack.get
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

run_test("notifies about remote updates", function()
  local notifications = check_with("abcdef1234567890", "0123456789abcdef")
  assert(#notifications == 1)
  assert_contains(notifications[1].message, "Plugin updates available (1)")
  assert_contains(notifications[1].message, "Run :lua vim.pack.update()")
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
replace_field(vim, "system", original_system)
replace_field(vim, "notify", original_notify)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
  vim.cmd("cquit 1")
end
