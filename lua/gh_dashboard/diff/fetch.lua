local M  = {}
local gh = require("gh_dashboard.gh")

-- ── helpers ────────────────────────────────────────────────────────────────

local function encode_path(path)
  local parts = {}
  for seg in path:gmatch("[^/]+") do
    table.insert(parts, vim.uri_encode(seg, "rfc3986"))
  end
  return table.concat(parts, "/")
end

-- ── pull request metadata ──────────────────────────────────────────────────

--- callback(err, { base_sha, head_sha, base_ref, head_ref, title, changed_files })
function M.fetch_meta(number, repo, callback)
  gh.run_with_retry(
    { "gh", "api", "repos/" .. repo .. "/pulls/" .. tostring(number), "--jq",
      "{base_sha:.base.sha, head_sha:.head.sha, base_ref:.base.ref, head_ref:.head.ref,"
      .. " title:.title, changed_files:.changed_files, state:.state}" },
    callback
  )
end

-- ── changed files ──────────────────────────────────────────────────────────

--- One paginated request returns every changed file with its patch, so the
--- unified view needs no further network calls.
--- callback(err, files) where each file is
--- { path, prev, status, add, del, patch, sha }
function M.fetch_files(number, repo, callback)
  vim.system(
    { "gh", "api", "repos/" .. repo .. "/pulls/" .. tostring(number) .. "/files?per_page=100",
      "--paginate", "--jq",
      ".[] | {path:.filename, prev:.previous_filename, status:.status,"
      .. " add:.additions, del:.deletions, patch:.patch, sha:.sha}" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(result.stderr ~= "" and result.stderr or "gh error", nil)
          return
        end
        local files = {}
        for line in (result.stdout or ""):gmatch("[^\n]+") do
          local ok, entry = pcall(vim.json.decode, line)
          if ok and type(entry) == "table" and entry.path then
            if entry.patch == vim.NIL then entry.patch = nil end
            if entry.prev  == vim.NIL then entry.prev  = nil end
            table.insert(files, entry)
          end
        end
        callback(nil, files)
      end)
    end
  )
end

-- ── blobs ──────────────────────────────────────────────────────────────────

--- Raw file content at a ref. callback(err, lines).
--- A missing file (added on one side) yields an empty list, not an error.
function M.fetch_blob(repo, path, ref, callback)
  vim.system(
    { "gh", "api", "repos/" .. repo .. "/contents/" .. encode_path(path) .. "?ref=" .. ref,
      "-H", "Accept: application/vnd.github.raw" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          local msg = result.stderr or ""
          if msg:match("404") or msg:match("[Nn]ot [Ff]ound") then
            callback(nil, {})
          else
            callback(msg ~= "" and msg or "blob fetch failed", nil)
          end
          return
        end
        local text = (result.stdout or ""):gsub("\r\n", "\n"):gsub("\n$", "")
        callback(nil, vim.split(text, "\n", { plain = true }))
      end)
    end
  )
end

-- ── review comments ────────────────────────────────────────────────────────

--- callback(comments) - never errors, returns {} on failure.
function M.fetch_review_comments(number, repo, callback)
  vim.system(
    { "gh", "api", "repos/" .. repo .. "/pulls/" .. tostring(number) .. "/comments?per_page=100",
      "--paginate", "--jq",
      ".[] | {login:.user.login, path:.path, line:(.line // .original_line),"
      .. " side:(.side // \"RIGHT\"), body:.body, created_at:.created_at,"
      .. " outdated:(.line == null), hunk:.diff_hunk}" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback({}) return end
        local out = {}
        for line in (result.stdout or ""):gmatch("[^\n]+") do
          local ok, c = pcall(vim.json.decode, line)
          if ok and type(c) == "table" then
            if c.line == vim.NIL then c.line = nil end
            table.insert(out, c)
          end
        end
        callback(out)
      end)
    end
  )
end

-- ── review submission ──────────────────────────────────────────────────────

--- Submit one review carrying every pending inline comment in a single request.
--- event: "APPROVE" | "REQUEST_CHANGES" | "COMMENT"
--- comments: { { path, line, side, start_line?, start_side?, body }, ... }
function M.submit_review(number, repo, commit_id, event, body, comments, callback)
  local payload = {
    commit_id = commit_id,
    event     = event,
    body      = body,
    comments  = comments,
  }
  if body == "" then payload.body = nil end
  if #comments == 0 then payload.comments = nil end

  vim.system(
    { "gh", "api", "repos/" .. repo .. "/pulls/" .. tostring(number) .. "/reviews",
      "--method", "POST", "--input", "-" },
    { text = true, stdin = vim.json.encode(payload) },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          local msg = (result.stdout ~= "" and result.stdout)
                   or (result.stderr ~= "" and result.stderr)
                   or "api error"
          callback(msg:gsub("[\n\r]", " "))
        else
          callback(nil)
        end
      end)
    end
  )
end

return M
