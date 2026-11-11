local M = {}
local git = require("vahti.git")

---@class VahtiConfig
---@field startup_delay number Milliseconds to wait after VimEnter.
---@field check_interval number Seconds between automatic checks.
---@field git_timeout number Milliseconds before a Git check is terminated.
---@field update_keymap string|false Key to open available updates in Telescope.
---@field telescope { max_width: number, max_height: number, select_all_by_default: boolean }
---@field messages { updates_with_telescope: string, updates_without_telescope: string }
local defaults = {
  startup_delay = 3000,
  check_interval = 24 * 60 * 60,
  git_timeout = 10000,
  update_keymap = "<leader>pu",
  telescope = {
    max_width = 150,
    max_height = 40,
    select_all_by_default = false,
  },
  messages = {
    updates_with_telescope = "Plugin updates available ({count}): {plugins}. {review_hint}.",
    updates_without_telescope = "Plugin updates available ({count}): {plugins}. Use :lua vim.pack.update() to review and apply.",
  },
}

---@class VahtiState
---@field last_check number

---@type VahtiConfig
local config = vim.deepcopy(defaults)
local state_file = vim.fn.stdpath("state") .. "/vahti.json"
local checking = false
local available_updates
local mapped_update_key

---@param updates table[]
---@return string[]
local function update_names(updates)
  local names = {}
  for _, update in ipairs(updates) do
    names[#names + 1] = type(update) == "table" and update.name or update
  end
  return names
end

local function has_telescope()
  return pcall(require, "telescope.pickers")
end

---@param updates table[]
---@return string
local function update_message(updates)
  local telescope_available = has_telescope()
  local template
  if telescope_available then
    template = config.messages.updates_with_telescope
  else
    template = config.messages.updates_without_telescope
  end

  local keymap = config.update_keymap or ":VahtiUpdate"
  local review_hint = config.update_keymap
      and ("Press " .. config.update_keymap .. " or run :VahtiUpdate to inspect in Telescope")
    or "Run :VahtiUpdate to inspect in Telescope"
  local replacements = {
    count = tostring(#updates),
    plugins = table.concat(update_names(updates), ", "),
    keymap = keymap,
    review_hint = review_hint,
  }

  return (template:gsub("{([%w_]+)}", function(key)
    return replacements[key] or ("{" .. key .. "}")
  end))
end

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
    messages[#messages + 1] = update_message(updates)
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
---@param on_complete? fun(updates: table[], failed: string[])
---@return boolean started Whether an asynchronous check was started.
function M.check(force, on_complete)
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
    available_updates = updates

    write_last_check()
    if on_complete then
      on_complete(updates, failed)
    else
      notify_result(updates, failed, force == true)
    end
  end)

  return true
end

local function open_telescope(updates)
  return require("vahti.telescope").open(updates, function()
    available_updates = nil
  end, config.telescope)
end

function M.update()
  local function open_updates(updates, failed)
    if #updates == 0 then
      notify_result(updates, failed, true)
      return
    end

    if #failed > 0 then
      notify_result({}, failed, false)
    end

    open_telescope(updates)
  end

  if available_updates and #available_updates > 0 then
    return open_telescope(available_updates)
  end

  local started = M.check(true, open_updates)

  if not started and checking then
    notify("An update check is already in progress.", vim.log.levels.WARN)
  end

  return started
end

---@param opts? { startup_delay?: number, check_interval?: number, git_timeout?: number, update_keymap?: string|false, telescope?: { max_width?: number, max_height?: number, select_all_by_default?: boolean }, messages?: { updates_with_telescope?: string, updates_without_telescope?: string } }
function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  assert(type(config.startup_delay) == "number" and config.startup_delay >= 0,
    "vahti: startup_delay must be a non-negative number")
  assert(type(config.check_interval) == "number" and config.check_interval >= 0,
    "vahti: check_interval must be a non-negative number")
  assert(type(config.git_timeout) == "number" and config.git_timeout > 0,
    "vahti: git_timeout must be a positive number")
  assert(config.update_keymap == false or (type(config.update_keymap) == "string" and config.update_keymap ~= ""),
    "vahti: update_keymap must be a non-empty string or false")
  assert(type(config.telescope.max_width) == "number" and config.telescope.max_width > 0,
    "vahti: telescope.max_width must be a positive number")
  assert(type(config.telescope.max_height) == "number" and config.telescope.max_height > 0,
    "vahti: telescope.max_height must be a positive number")
  assert(type(config.telescope.select_all_by_default) == "boolean",
    "vahti: telescope.select_all_by_default must be a boolean")
  assert(type(config.messages) == "table", "vahti: messages must be a table")
  assert(type(config.messages.updates_with_telescope) == "string",
    "vahti: messages.updates_with_telescope must be a string")
  assert(type(config.messages.updates_without_telescope) == "string",
    "vahti: messages.updates_without_telescope must be a string")

  if mapped_update_key and mapped_update_key ~= config.update_keymap then
    pcall(vim.keymap.del, "n", mapped_update_key)
  end
  mapped_update_key = config.update_keymap
  if mapped_update_key then
    vim.keymap.set("n", mapped_update_key, M.update, { desc = "Review vim.pack plugin updates" })
  end

  return M
end

function M._on_vimenter()
  vim.defer_fn(function()
    M.check(false)
  end, config.startup_delay)
end

M.setup()

return M
