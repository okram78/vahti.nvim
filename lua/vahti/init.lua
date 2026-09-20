local M = {}

---@class VahtiConfig
---@field startup_delay number Milliseconds to wait after VimEnter.
---@field check_interval number Seconds between automatic checks.
local defaults = {
  startup_delay = 3000,
  check_interval = 24 * 60 * 60,
}

---@class VahtiState
---@field last_check number

---@type VahtiConfig
local config = vim.deepcopy(defaults)
local state_file = vim.fn.stdpath("state") .. "/vahti.json"
local checking = false

---@param message string
---@param level? integer
local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "vahti.nvim" })
end

---@return number?
local function read_last_check()
  local file = io.open(state_file, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  local ok, state = pcall(vim.json.decode, content)
  if ok and type(state) == "table" then
    ---@cast state VahtiState
    if type(state.last_check) == "number" then
      return state.last_check
    end
  end
end

local function write_last_check()
  vim.fn.mkdir(vim.fn.stdpath("state"), "p")

  local file = io.open(state_file, "w")
  if not file then
    return
  end

  file:write(vim.json.encode({ last_check = os.time() }))
  file:close()
end

local function check_version()
  local version = vim.version()
  if version.major > 0 or version.minor >= 12 then
    return true
  end

  notify("vahti.nvim requires Neovim 0.12 or newer", vim.log.levels.ERROR)
  return false
end

local function update_command()
  if vim.fn.exists(":PackUpdate") == 2 then
    return ":PackUpdate"
  end
  return ":lua vim.pack.update()"
end

---@param plugin vim.pack.PlugData
---@return string
local function update_target(plugin)
  if type(plugin.spec.version) == "string" then
    return plugin.spec.version
  end
  return "HEAD"
end

---@param plugins vim.pack.PlugData[]
---@param on_complete fun(updates: string[], failed: string[])
local function check_remote_revisions(plugins, on_complete)
  if #plugins == 0 then
    on_complete({}, {})
    return
  end

  local remaining = #plugins
  local updates = {}
  local failed = {}

  local function complete_one()
    remaining = remaining - 1
    if remaining == 0 then
      vim.schedule(function()
        on_complete(updates, failed)
      end)
    end
  end

  for _, plugin in ipairs(plugins) do
    vim.system({ "git", "ls-remote", plugin.spec.src, update_target(plugin) }, { text = true }, function(result)
      if result.code ~= 0 then
        failed[#failed + 1] = plugin.spec.name
      else
        local remote_revision = result.stdout:match("^(%x+)%s")
        if remote_revision and remote_revision ~= plugin.rev then
          updates[#updates + 1] = plugin.spec.name
        end
      end
      complete_one()
    end)
  end
end

---@param updates string[]
local function notify_updates(updates)
  if #updates == 0 then
    return
  end

  notify(string.format(
    "Plugin updates available (%d): %s. Run %s to review and apply.",
    #updates,
    table.concat(updates, ", "),
    update_command()
  ))
end

---@param force? boolean
---@return boolean
function M.check(force)
  if checking then
    return false
  end

  if not check_version() or type(vim.pack) ~= "table" then
    notify("vahti.nvim requires Neovim's vim.pack", vim.log.levels.ERROR)
    return false
  end

  if not force then
    local last_check = read_last_check()
    if last_check and os.time() - last_check < config.check_interval then
      return false
    end
  end

  local ok, plugins = pcall(vim.pack.get)
  if not ok then
    notify("Could not inspect vim.pack plugins: " .. tostring(plugins), vim.log.levels.WARN)
    return false
  end

  checking = true
  check_remote_revisions(plugins, function(updates, failed)
    checking = false

    if #failed > 0 then
      notify("Could not check updates for: " .. table.concat(failed, ", "), vim.log.levels.WARN)
      return
    end

    write_last_check()
    notify_updates(updates)
  end)

  return true
end

---@param opts? { startup_delay?: number, check_interval?: number }
function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  assert(type(config.startup_delay) == "number" and config.startup_delay >= 0,
    "vahti: startup_delay must be a non-negative number")
  assert(type(config.check_interval) == "number" and config.check_interval >= 0,
    "vahti: check_interval must be a non-negative number")

  return M
end

function M._on_vimenter()
  vim.defer_fn(function()
    M.check(false)
  end, config.startup_delay)
end

M.setup()

return M
