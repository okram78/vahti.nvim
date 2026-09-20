if vim.g.loaded_vahti then
  return
end
vim.g.loaded_vahti = true

vim.api.nvim_create_user_command("VahtiCheck", function()
  require("vahti").check(true)
end, { desc = "Check vim.pack plugins for updates" })

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("vahti", { clear = true }),
  callback = function()
    require("vahti")._on_vimenter()
  end,
})
