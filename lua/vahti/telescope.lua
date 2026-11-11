local M = {}
local git = require("vahti.git")
local preview_namespace = vim.api.nvim_create_namespace("vahti-telescope-preview")

local function notify(message, level)
  vim.notify(message, level, { title = "vahti.nvim" })
end

---@param updates table[]
---@param on_apply? fun(names: string[])
---@param opts? { max_width?: number, max_height?: number, select_all_by_default?: boolean }
function M.open(updates, on_apply, opts)
  opts = opts or {}
  local max_width = opts.max_width or 150
  local max_height = opts.max_height or 40

  local ok, telescope = pcall(function()
    return {
      actions = require("telescope.actions"),
      action_state = require("telescope.actions.state"),
      finders = require("telescope.finders"),
      pickers = require("telescope.pickers"),
      previewers = require("telescope.previewers"),
      sorters = require("telescope.sorters"),
    }
  end)

  if not ok then
    notify("Telescope.nvim is required for :VahtiUpdate.", vim.log.levels.ERROR)
    return false
  end

  local function preview_lines(update)
    local target = (update.remote_ref or ""):gsub("^refs/heads/", ""):gsub("^refs/tags/", "")
    local lines = {
      "## " .. update.name,
      "Path:            " .. (update.path or "Unknown"),
      "Source:          " .. (update.src or "Unknown"),
      "Revision before: " .. (update.rev_before or "Unknown"),
      "Revision after:  " .. (update.rev_after or "Unknown") .. (target ~= "" and (" (" .. target .. ")") or ""),
      "",
      "Pending updates:",
    }

    if update.details_error then
      vim.list_extend(lines, { "Could not load pending updates:", update.details_error })
    elseif update.details then
      if update.details == "" then
        lines[#lines + 1] = "No commit details found."
      else
        vim.list_extend(lines, vim.split(update.details, "\n", { plain = true }))
      end
    else
      lines[#lines + 1] = "Loading commit details..."
    end

    return lines
  end

  local function set_preview(bufnr, update)
    local lines = preview_lines(update)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(bufnr, preview_namespace, 0, -1)
    vim.bo[bufnr].filetype = "text"

    local function highlight(group, row, start_col, end_col)
      vim.api.nvim_buf_set_extmark(bufnr, preview_namespace, row, start_col, {
        end_row = row,
        end_col = end_col,
        hl_group = group,
      })
    end

    for line_number, line in ipairs(lines) do
      local row = line_number - 1
      if line:match("^##? ") then
        highlight("Title", row, 0, #line)
      elseif line:match("^> ") then
        highlight("Added", row, 0, #line)
      elseif line:match("^< ") then
        highlight("Removed", row, 0, #line)
      elseif line:match("^Pending updates:") then
        highlight("Special", row, 0, #line)
      else
        local label_end = line:find(":%s+")
        if label_end then
          highlight("Comment", row, 0, label_end)
          local value_start = line:find("%S", label_end + 1)
          local is_path = line:match("^Path:") or line:match("^Source:")
          local value_group
          if is_path then
            value_group = "Directory"
          else
            value_group = "Identifier"
          end
          if value_start then
            highlight(value_group, row, value_start - 1, #line)
          end
        end
      end
    end
  end

  local previewer = telescope.previewers.new_buffer_previewer({
    define_preview = function(self, entry)
      local update = entry.value
      local bufnr = self.state.bufnr
      self.state.vahti_update = update
      set_preview(bufnr, update)

      if not update.details and not update.details_error then
        git.get_update_details(update, update.git_timeout, function()
          if self.state.vahti_update == update and vim.api.nvim_buf_is_valid(bufnr) then
            set_preview(bufnr, update)
          end
        end)
      end
    end,
  })

  local picker = telescope.pickers.new({}, {
    prompt_title = opts.select_all_by_default
        and "Plugin updates · all selected · <Tab> toggle · <CR> update"
      or "Plugin updates · <Tab> select · <CR> update",
    results_title = "Plugin updates",
    preview_title = "Pending update details",
    previewer = previewer,
    layout_strategy = "horizontal",
    layout_config = {
      width = function(_, columns)
        return math.min(max_width, math.floor(columns * 0.9))
      end,
      height = function(_, _, lines)
        return math.min(max_height, math.floor(lines * 0.85))
      end,
      preview_width = 0.55,
    },
    finder = telescope.finders.new_table({
      results = updates,
      entry_maker = function(update)
        return { value = update, display = update.name, ordinal = update.name }
      end,
    }),
    sorter = telescope.sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr)
      telescope.actions.select_default:replace(function()
        local current_picker = telescope.action_state.get_current_picker(prompt_bufnr)
        local selected = current_picker:get_multi_selection()

        if #selected == 0 then
          local entry = telescope.action_state.get_selected_entry()
          if entry then
            selected = { entry }
          end
        end

        local names = {}
        for _, entry in ipairs(selected) do
          names[#names + 1] = entry.value.name
        end

        telescope.actions.close(prompt_bufnr)
        if #names == 0 then
          return
        end

        local updated, err = pcall(vim.pack.update, names, { force = true })
        if not updated then
          notify("Could not update plugins: " .. tostring(err), vim.log.levels.ERROR)
        elseif on_apply then
          on_apply(names)
        end
      end)

      return true
    end,
  })

  if opts.select_all_by_default then
    local selected_all = false
    picker:register_completion_callback(function(completed_picker)
      if selected_all then
        return
      end

      selected_all = true
      telescope.actions.select_all(completed_picker.prompt_bufnr)
    end)
  end

  picker:find()
  return true
end

return M
