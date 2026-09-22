local M          = {}
local review     = require("gh_dashboard.diff.review")
local diff_fetch = require("gh_dashboard.diff.fetch")

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

--- Reviews queued in the diff viewer belong to the same review as this summary,
--- so they ride along instead of being left behind. Only that case needs the
--- head sha, so the plain CLI call still covers a summary on its own.
function M.submit_review(item, kind, body, callback)
  local key = review.key(item.repo, item.number)
  if review.count(key) > 0 then
    local event = kind == "approve" and "APPROVE"
      or kind == "request_changes" and "REQUEST_CHANGES"
      or "COMMENT"
    diff_fetch.fetch_meta(item.number, item.repo, function(err, meta)
      if err then callback(err) return end
      review.submit(key, item.number, item.repo, meta.head_sha, event, body, callback)
    end)
    return
  end

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
