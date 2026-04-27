if vim.g.gh_dashboard_loaded then return end
vim.g.gh_dashboard_loaded = true

vim.api.nvim_create_user_command("GhDashboard", function()
  require("gh_dashboard").toggle()
end, { desc = "Toggle GitHub Dashboard" })

vim.api.nvim_create_user_command("GhWatchlist", function()
  require("gh_dashboard.watchlist").toggle()
end, { desc = "Toggle GitHub Watchlist manager" })

vim.api.nvim_create_user_command("GhNotifications", function()
  require("gh_dashboard.notifications").toggle()
end, { desc = "Toggle GitHub Notifications" })

vim.api.nvim_create_user_command("GhRepoPicker", function()
  require("gh_dashboard.repo_picker").open()
end, { desc = "Fuzzy search GitHub repos" })

vim.api.nvim_create_user_command("GhDebug", function()
  require("gh_dashboard").debug()
end, { desc = "Show GhDashboard debug info" })
