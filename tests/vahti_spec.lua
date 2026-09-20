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

local function check_with(remote_revision, current_revision, exit_code)
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
        },
      },
    }
  end)
  replace_field(vim, "system", function(_, _, callback)
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

run_test("does not notify when revisions match", function()
  local notifications = check_with("abcdef1234567890", "abcdef1234567890")
  assert(#notifications == 0)
end)

run_test("warns when Git check fails", function()
  local notifications = check_with("abcdef1234567890", "0123456789abcdef", 1)
  assert(#notifications == 1)
  assert_contains(notifications[1].message, "Could not check updates for")
end)

replace_field(vim.pack, "get", original_get)
replace_field(vim, "system", original_system)
replace_field(vim, "notify", original_notify)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
  vim.cmd("cquit 1")
end
