local M = {}

M.check = function()
  vim.health.start("gh_dashboard")

  if vim.fn.executable("gh") == 1 then
    vim.health.ok("gh CLI found: " .. vim.fn.system("gh --version"):match("[^\n]+"))
  else
    vim.health.error("gh CLI not found", { "Install gh: https://cli.github.com" })
    return
  end

  local auth = vim.fn.system("gh auth status 2>&1")
  if vim.v.shell_error == 0 then
    vim.health.ok("gh authenticated")
  else
    vim.health.error("gh not authenticated", { "Run: gh auth login" })
    return
  end

  if auth:find("read:user") or auth:find("read_user") then
    vim.health.ok("read:user scope present")
  else
    vim.health.warn("read:user scope not confirmed", { "Run: gh auth refresh -s read:user" })
  end
end

return M
