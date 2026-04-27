local M  = {}
local gh = require("gh_dashboard.gh")

-- ── helpers ────────────────────────────────────────────────────────────────

local function safe_str(v)
  if v == nil or v == vim.NIL then return "" end
  return tostring(v)
end

local function safe_list(v)
  if type(v) ~= "table" then return {} end
  return v
end

-- ── fetch functions ────────────────────────────────────────────────────────

function M.fetch_readme(item, callback)
  vim.system(
    { "gh", "api", "repos/" .. item.full_name .. "/readme",
      "-H", "Accept: application/vnd.github.raw" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback("No README found", nil)
          return
        end
        callback(nil, result.stdout)
      end)
    end
  )
end

function M.fetch_issue(item, callback)
  gh.run_with_retry(
    { "gh", "issue", "view", tostring(item.number), "-R", item.repo,
      "--json", "number,title,state,body,labels,author,comments,createdAt,assignees,url" },
    function(err, raw)
      if err then callback(err, nil) return end
      local labels = {}
      for _, l in ipairs(safe_list(raw.labels)) do
        if type(l) == "table" and l.name then
          table.insert(labels, l.name)
        end
      end
      local comments = {}
      for _, c in ipairs(safe_list(raw.comments)) do
        table.insert(comments, {
          id         = safe_str(c.id),
          author     = type(c.author) == "table" and safe_str(c.author.login) or "?",
          body       = safe_str(c.body),
          created_at = safe_str(c.createdAt),
        })
      end
      callback(nil, {
        kind       = "issue",
        number     = raw.number,
        title      = safe_str(raw.title),
        state      = safe_str(raw.state),
        body       = safe_str(raw.body),
        labels     = labels,
        author     = type(raw.author) == "table" and safe_str(raw.author.login) or "?",
        created_at = safe_str(raw.createdAt),
        url        = safe_str(raw.url),
        comments   = comments,
      })
    end
  )
end

function M.fetch_pr(item, callback)
  gh.run_with_retry(
    { "gh", "pr", "view", tostring(item.number), "-R", item.repo,
      "--json", "number,title,state,body,author,headRefName,baseRefName,reviews,statusCheckRollup,comments,createdAt,isDraft,mergeable,url,assignees" },
    function(err, raw)
      if err then callback(err, nil) return end
      local labels = {}
      for _, l in ipairs(safe_list(raw.labels)) do
        if type(l) == "table" and l.name then table.insert(labels, l.name) end
      end
      local reviews = {}
      for _, r in ipairs(safe_list(raw.reviews)) do
        table.insert(reviews, {
          author       = type(r.author) == "table" and safe_str(r.author.login) or "?",
          state        = safe_str(r.state),
          body         = safe_str(r.body),
          submitted_at = safe_str(r.submittedAt),
        })
      end
      local ci_checks = {}
      for _, c in ipairs(safe_list(raw.statusCheckRollup)) do
        table.insert(ci_checks, {
          name       = safe_str(c.name or c.context),
          status     = safe_str(c.status or c.state),
          conclusion = c.conclusion ~= vim.NIL and safe_str(c.conclusion) or nil,
        })
      end
      local comments = {}
      for _, c in ipairs(safe_list(raw.comments)) do
        table.insert(comments, {
          id         = safe_str(c.id),
          author     = type(c.author) == "table" and safe_str(c.author.login) or "?",
          body       = safe_str(c.body),
          created_at = safe_str(c.createdAt),
        })
      end
      callback(nil, {
        kind       = "pr",
        number     = raw.number,
        title      = safe_str(raw.title),
        state      = safe_str(raw.state),
        body       = safe_str(raw.body),
        author     = type(raw.author) == "table" and safe_str(raw.author.login) or "?",
        head_ref   = safe_str(raw.headRefName),
        base_ref   = safe_str(raw.baseRefName),
        is_draft   = raw.isDraft == true,
        mergeable  = safe_str(raw.mergeable),
        created_at = safe_str(raw.createdAt),
        url        = safe_str(raw.url),
        labels     = labels,
        reviews    = reviews,
        ci_checks  = ci_checks,
        comments   = comments,
      })
    end
  )
end

function M.fetch_review_comments(number, repo, callback)
  vim.system(
    { "gh", "api", "repos/" .. repo .. "/pulls/" .. tostring(number) .. "/comments",
      "--jq", "[.[] | {login: .user.login, path: .path, line: (.line // .original_line), body: .body, hunk: .diff_hunk}]" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback({}) return end
        local ok, data = pcall(vim.json.decode, result.stdout or "[]")
        callback(ok and type(data) == "table" and data or {})
      end)
    end
  )
end

function M.fetch_head_sha(number, repo, callback)
  vim.system(
    { "gh", "pr", "view", tostring(number), "--repo", repo,
      "--json", "headRefOid", "--jq", ".headRefOid" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(result.stderr or "gh error", nil)
        else
          callback(nil, vim.trim(result.stdout or ""))
        end
      end)
    end
  )
end

function M.fetch_diff(number, repo, callback)
  vim.system(
    { "gh", "pr", "diff", tostring(number), "--repo", repo },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(result.stderr or "gh error", nil)
        else
          callback(nil, result.stdout or "")
        end
      end)
    end
  )
end

function M.post_review_comment(number, repo, sha, path, line, side, body, callback)
  vim.system(
    { "gh", "api", "repos/" .. repo .. "/pulls/" .. tostring(number) .. "/comments",
      "-f", "body=" .. body,
      "-f", "commit_id=" .. sha,
      "-f", "path=" .. path,
      "-F", "line=" .. tostring(line),
      "-f", "side=" .. side },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          local msg = (result.stdout ~= "" and result.stdout)
                   or (result.stderr ~= "" and result.stderr)
                   or "api error"
          callback(msg)
        else
          callback(nil)
        end
      end)
    end
  )
end

return M
