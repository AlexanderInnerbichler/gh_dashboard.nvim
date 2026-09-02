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

vim.api.nvim_create_user_command("GhDiff", function(cmd)
  local diff = function(number, repo)
    require("gh_dashboard.diff").open({ number = number, repo = repo, kind = "pr" })
  end

  local number = tonumber(cmd.fargs[1])
  if number and cmd.fargs[2] then
    diff(number, cmd.fargs[2])
    return
  end

  if number then
    vim.system({ "gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner" },
      { text = true }, function(r)
        vim.schedule(function()
          if r.code ~= 0 then
            vim.notify("Not in a GitHub repo — try :GhDiff <n> owner/repo", vim.log.levels.ERROR)
            return
          end
          diff(number, vim.trim(r.stdout))
        end)
      end)
    return
  end

  -- no argument: diff the pull request for the current branch
  vim.system({ "gh", "pr", "view", "--json", "url", "--jq", ".url" }, { text = true }, function(r)
    vim.schedule(function()
      local url = vim.trim(r.stdout or "")
      local owner, name, n = url:match("github%.com/([^/]+)/([^/]+)/pull/(%d+)")
      if r.code ~= 0 or not n then
        vim.notify("No pull request found for the current branch — try :GhDiff <n>",
          vim.log.levels.ERROR)
        return
      end
      diff(tonumber(n), owner .. "/" .. name)
    end)
  end)
end, { desc = "Diff a pull request (current branch if no argument)", nargs = "*" })

vim.api.nvim_create_user_command("GhDebug", function()
  require("gh_dashboard").debug()
end, { desc = "Show GhDashboard debug info" })

vim.keymap.set("n", "<leader>gn", function()
  require("gh_dashboard.notifications").toggle()
end, { desc = "Toggle GitHub Notifications" })
