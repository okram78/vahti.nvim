local M = {}
local git = require("vahti.git")

---@class VahtiConfig
---@field startup_delay number Milliseconds to wait after VimEnter.
---@field check_interval number Seconds between automatic checks.
---@field git_timeout number Milliseconds before a Git check is terminated.
local defaults = {
  startup_delay = 3000,
  check_interval = 24 * 60 * 60,
  git_timeout = 10000,
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

---@param updates string[]
---@param failed string[]
---@param notify_empty boolean
local function notify_result(updates, failed, notify_empty)
  local messages = {}

  if #updates > 0 then
    messages[#messages + 1] = string.format(
      "Plugin updates available (%d): %s. Run :lua vim.pack.update() to review and apply.",
      #updates,
      table.concat(updates, ", ")
    )
  end

  if #failed > 0 then
    messages[#messages + 1] = "Could not check: " .. table.concat(failed, ", ")
  end

  if #messages == 0 then
    if notify_empty then
      notify("No plugin updates available.")
    end
    return
  end

  notify(table.concat(messages, "\n"), #failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
end

---@param force? boolean
---@return boolean started Whether an asynchronous check was started.
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
  git.check_revisions(plugins, config.git_timeout, function(updates, failed)
    checking = false

    write_last_check()
    notify_result(updates, failed, force == true)
  end)

  return true
end

---@param opts? { startup_delay?: number, check_interval?: number, git_timeout?: number }
function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  assert(type(config.startup_delay) == "number" and config.startup_delay >= 0,
    "vahti: startup_delay must be a non-negative number")
  assert(type(config.check_interval) == "number" and config.check_interval >= 0,
    "vahti: check_interval must be a non-negative number")
  assert(type(config.git_timeout) == "number" and config.git_timeout > 0,
    "vahti: git_timeout must be a positive number")

  return M
end

function M._on_vimenter()
  vim.defer_fn(function()
    M.check(false)
  end, config.startup_delay)
end

M.setup()

return M
