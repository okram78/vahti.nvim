if vim.g.loaded_vahti then
  return
end
vim.g.loaded_vahti = true

local group = vim.api.nvim_create_augroup("vahti", { clear = true })

vim.api.nvim_create_user_command("VahtiCheck", function()
  require("vahti").check(true)
end, { desc = "Check vim.pack plugins for updates" })

vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  callback = function()
    require("vahti")._on_vimenter()
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "nvim-pack",
  callback = function(args)
    local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:match("^# Update") then
        vim.notify(
          "Plugin updates are available. Review the nvim-pack buffer; use :write to apply or :quit to cancel.",
          vim.log.levels.INFO,
          { title = "vahti.nvim" }
        )
        return
      end
    end
  end,
})
