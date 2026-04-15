if vim.g.gh_dashboard_loaded then return end
vim.g.gh_dashboard_loaded = true

vim.api.nvim_create_user_command("GhDashboard", function()
  require("gh_dashboard").toggle()
end, { desc = "Toggle GitHub Dashboard" })

vim.api.nvim_create_user_command("GhWatchlist", function()
  require("gh_dashboard.watchlist").toggle()
end, { desc = "Toggle GitHub Watchlist manager" })
