local M = {}

---@param plugin vim.pack.PlugData
---@return string, boolean
local function update_target(plugin)
  -- vim.pack's version is passed to Git as a literal ref, such as a tag.
  if type(plugin.spec.version) == "string" then
    return tostring(plugin.spec.version), false
  elseif plugin.spec.version == nil then
    return "HEAD", false
  end
  return "", true
end

---@param output string
---@param version_range vim.VersionRange
---@return string?
local function resolve_version_range(output, version_range)
  local revisions = {}

  for line in output:gmatch("[^\n]+") do
    local revision, tag = line:match("^(%x+)%s+refs/tags/(.+)$")
    if revision and tag then
      local peeled_tag = tag:match("^(.-)%^%{%}$")
      if peeled_tag then
        revisions[peeled_tag] = revision
      else
        revisions[tag] = revision
      end
    end
  end

  local selected_tag
  local selected_version
  for tag, revision in pairs(revisions) do
    local version = vim.version.parse(tag, { strict = true })
    if version and version_range:has(version) and (not selected_version or version > selected_version) then
      selected_tag = revision
      selected_version = version
    end
  end

  return selected_tag
end

---@param plugins vim.pack.PlugData[]
---@param timeout number
---@param on_complete fun(updates: string[], failed: string[])
function M.check_revisions(plugins, timeout, on_complete)
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
    local target, is_version_range = update_target(plugin)
    local command = { "git", "ls-remote", plugin.spec.src, target }
    if is_version_range then
      command = { "git", "ls-remote", "--tags", plugin.spec.src }
    end

    vim.system(command, {
      text = true,
      timeout = timeout,
    }, function(result)
      if result.code ~= 0 then
        failed[#failed + 1] = plugin.spec.name
      else
        local remote_revision
        if is_version_range then
          local version_range = plugin.spec.version
          ---@cast version_range vim.VersionRange
          remote_revision = resolve_version_range(result.stdout, version_range)
        else
          remote_revision = result.stdout:match("^(%x+)%s")
        end
        if not remote_revision then
          failed[#failed + 1] = plugin.spec.name
        elseif remote_revision ~= plugin.rev then
          updates[#updates + 1] = plugin.spec.name
        end
      end
      complete_one()
    end)
  end
end

return M
