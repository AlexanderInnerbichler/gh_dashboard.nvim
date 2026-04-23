local M = {}

-- ── action functions ───────────────────────────────────────────────────────

function M.post_comment(item, body, callback)
  local cmd = item.kind == "issue"
    and { "gh", "issue", "comment", tostring(item.number), "-R", item.repo, "--body", body }
    or  { "gh", "pr",    "comment", tostring(item.number), "-R", item.repo, "--body", body }
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then callback(result.stderr or "gh error")
      else callback(nil) end
    end)
  end)
end

function M.submit_review(item, kind, body, callback)
  local flag = kind == "approve" and "--approve"
    or kind == "request_changes" and "--request-changes"
    or "--comment"
  vim.system(
    { "gh", "pr", "review", tostring(item.number), "-R", item.repo, flag, "--body", body },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback(result.stderr or "gh error")
        else callback(nil) end
      end)
    end
  )
end

function M.merge_pr(item, method, callback)
  local flag = method == "squash" and "--squash" or method == "rebase" and "--rebase" or "--merge"
  vim.system(
    { "gh", "pr", "merge", tostring(item.number), "-R", item.repo, flag },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback(result.stderr or "gh error")
        else callback(nil) end
      end)
    end
  )
end

function M.close_issue(item, callback)
  vim.system(
    { "gh", "issue", "close", tostring(item.number), "-R", item.repo },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback(result.stderr or "gh error")
        else callback(nil) end
      end)
    end
  )
end

function M.create_issue(repo, title, body, callback)
  vim.system(
    { "gh", "issue", "create", "-R", repo, "--title", title, "--body", body, "--assignee", "@me" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback(result.stderr or "gh error")
        else callback(nil) end
      end)
    end
  )
end

return M
