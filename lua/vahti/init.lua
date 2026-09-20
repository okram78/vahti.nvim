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

---@class VahtiPackData: vim.pack.PlugData
---@field rev_to? string

---@type VahtiConfig
local config = vim.deepcopy(defaults)
local state_file = vim.fn.stdpath("state") .. "/vahti.json"

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

---@return VahtiPackData[]?
local function find_updates()
  local ok, plugins = pcall(vim.pack.get, nil, { info = true, offline = false })
  if not ok then
    notify("Could not check plugin updates: " .. tostring(plugins), vim.log.levels.WARN)
    return nil
  end

  ---@cast plugins VahtiPackData[]
  local updates = {}
  for _, plugin in ipairs(plugins) do
    if plugin.rev_to and plugin.rev_to ~= plugin.rev then
      updates[#updates + 1] = plugin.spec.name
    end
  end

  return updates
end

---@param force? boolean
---@return boolean
function M.check(force)
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

  local updates = find_updates()
  if not updates then
    return false
  end

  write_last_check()

  if #updates == 0 then
    return true
  end

  notify(
    string.format(
      "%d plugin update%s available: %s. Run :packupdate to review and apply.",
      #updates,
      #updates == 1 and " is" or "s are",
      table.concat(updates, ", ")
    )
  )
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
