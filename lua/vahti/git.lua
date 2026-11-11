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
---@return string?, string?
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
  local selected_ref
  local selected_version
  for tag, revision in pairs(revisions) do
    local version = vim.version.parse(tag, { strict = true })
    if version and version_range:has(version) and (not selected_version or version > selected_version) then
      selected_tag = revision
      selected_ref = tag
      selected_version = version
    end
  end

  return selected_tag, selected_ref
end

---@param plugins vim.pack.PlugData[]
---@param timeout number
---@param on_complete fun(updates: table[], failed: string[])
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
        local remote_ref
        if is_version_range then
          local version_range = plugin.spec.version
          ---@cast version_range vim.VersionRange
          local remote_tag
          remote_revision, remote_tag = resolve_version_range(result.stdout, version_range)
          remote_ref = remote_tag and ("refs/tags/" .. remote_tag)
        else
          remote_revision, remote_ref = result.stdout:match("^(%x+)%s+([^%s]+)")
        end
        if not remote_revision then
          failed[#failed + 1] = plugin.spec.name
        elseif remote_revision ~= plugin.rev then
          updates[#updates + 1] = {
            name = plugin.spec.name,
            path = plugin.path,
            src = plugin.spec.src,
            rev_before = plugin.rev,
            rev_after = remote_revision,
            remote_ref = remote_ref,
            git_timeout = timeout,
          }
        end
      end
      complete_one()
    end)
  end
end

---@param update table
---@param timeout number
---@param on_complete fun(details: string?, err: string?)
function M.get_update_details(update, timeout, on_complete)
  if update.details then
    on_complete(update.details, update.details_error)
    return
  end

  update.detail_callbacks = update.detail_callbacks or {}
  update.detail_callbacks[#update.detail_callbacks + 1] = on_complete
  if update.details_loading then
    return
  end
  update.details_loading = true

  local function finish(details, err)
    update.details = details or ""
    update.details_error = err
    update.details_loading = false
    local callbacks = update.detail_callbacks
    update.detail_callbacks = nil
    for _, callback in ipairs(callbacks) do
      callback(update.details, update.details_error)
    end
  end

  local fetch = {
    "git",
    "fetch",
    "--quiet",
    "--tags",
    "--force",
    update.src,
    update.remote_ref,
  }
  vim.system(fetch, { cwd = update.path, text = true, timeout = timeout }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        finish(nil, (result.stderr or "Git fetch failed"):gsub("%s+$", ""))
        return
      end

      local range = update.rev_before .. "..." .. update.rev_after
      local sides = { "--left-only", "--right-only" }
      local remaining = #sides
      local details = {}
      local log_failed

      for _, side in ipairs(sides) do
        vim.system({
          "git",
          "log",
          "--pretty=format:%m %h │ %s%d",
          "--topo-order",
          side,
          "--decorate-refs=refs/tags",
          range,
        }, { cwd = update.path, text = true, timeout = timeout }, function(log_result)
          vim.schedule(function()
            if log_result.code ~= 0 then
              log_failed = (log_result.stderr or "Could not read pending commits"):gsub("%s+$", "")
            elseif log_result.stdout and log_result.stdout ~= "" then
              details[#details + 1] = log_result.stdout
            end

            remaining = remaining - 1
            if remaining == 0 then
              finish(table.concat(details, "\n"), log_failed)
            end
          end)
        end)
      end
    end)
  end)
end

return M
