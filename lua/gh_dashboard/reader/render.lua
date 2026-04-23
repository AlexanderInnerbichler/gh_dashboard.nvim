local M = {}

-- ── constants ──────────────────────────────────────────────────────────────

local CODE_WIDTH = 70

-- ── helpers ────────────────────────────────────────────────────────────────

local function separator()
  return "  " .. string.rep("─", CODE_WIDTH + 2)
end

local function age_string(iso8601)
  if not iso8601 or iso8601 == vim.NIL then return "" end
  local y, mo, d, h, mi, s = iso8601:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t    = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                         hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
  local tz   = os.difftime(t, os.time(os.date("!*t", t)))
  local diff = os.time() - (t + tz)
  if diff < 3600 then
    return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. "h ago"
  elseif diff < 604800 then
    return math.floor(diff / 86400) .. "d ago"
  else
    return math.floor(diff / 604800) .. "w ago"
  end
end

local function safe_str(v)
  if v == nil or v == vim.NIL then return "" end
  return tostring(v)
end

local function sl(s)
  return s:gsub("[\n\r]", " ")
end

local function state_hl(s)
  local upper = s:upper()
  if upper == "OPEN"   then return "GhReaderStateOpen"
  elseif upper == "MERGED" then return "GhReaderStateMerged"
  else return "GhReaderStateClosed"
  end
end

-- ── body renderer ─────────────────────────────────────────────────────────

local function process_body(body, lines, hl_specs)
  if body == "" then
    local msg = "   (no description)"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhReaderEmpty", line = #lines - 1, col_s = 0, col_e = -1 })
    return
  end
  local in_code = false
  for raw in (body .. "\n"):gmatch("([^\n]*)\n") do
    if raw:match("^```") then
      if in_code then
        table.insert(lines, "  ╰" .. string.rep("─", CODE_WIDTH) .. "╯")
        table.insert(hl_specs, { hl = "GhReaderCode", line = #lines - 1, col_s = 0, col_e = -1 })
        in_code = false
      else
        local lang  = (raw:match("^```(.-)%s*$") or ""):gsub("%s+", "")
        local label = lang ~= "" and (" " .. lang .. " ") or ""
        local fill  = string.rep("─", math.max(0, CODE_WIDTH - #label - 1))
        table.insert(lines, "  ╭─" .. label .. fill .. "╮")
        table.insert(hl_specs, { hl = "GhReaderCode", line = #lines - 1, col_s = 0, col_e = -1 })
        in_code = true
      end
    elseif in_code then
      table.insert(lines, "  │ " .. raw)
      table.insert(hl_specs, { hl = "GhReaderCodeBody", line = #lines - 1, col_s = 0, col_e = -1 })
    elseif raw:match("^> ") then
      local quote = raw:match("^> (.*)$") or ""
      table.insert(lines, "  ┃ " .. quote)
      table.insert(hl_specs, { hl = "GhReaderQuote", line = #lines - 1, col_s = 0, col_e = -1 })
    elseif raw:match("^(#+) ") then
      local level   = #(raw:match("^(#+) "))
      local heading = raw:match("^#+%s+(.+)$") or ""
      table.insert(lines, "")
      if level <= 2 then
        table.insert(lines, "  " .. heading)
        table.insert(hl_specs, { hl = "GhReaderH2", line = #lines - 1, col_s = 2, col_e = -1 })
        table.insert(lines, "  " .. string.rep("─", math.min(#heading, CODE_WIDTH)))
        table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
      else
        table.insert(lines, "  ▸ " .. heading)
        table.insert(hl_specs, { hl = "GhReaderH3", line = #lines - 1, col_s = 2, col_e = -1 })
      end
    elseif raw:match("^%s*[%-%*%+] ") then
      local item = raw:match("^%s*[%-%*%+] (.*)$") or ""
      table.insert(lines, "  • " .. item)
      table.insert(hl_specs, { hl = "GhReaderBullet", line = #lines - 1, col_s = 2, col_e = 5 })
    elseif raw:match("^%s*%d+%. ") then
      local item = raw:match("^%s*(%d+%..*)$") or raw
      table.insert(lines, "  " .. item)
    elseif raw:match("^%-%-%-+$") or raw:match("^%*%*%*+$") or raw:match("^___+$") then
      table.insert(lines, "  " .. string.rep("─", CODE_WIDTH))
      table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    else
      table.insert(lines, "  " .. raw)
    end
  end
  if in_code then
    table.insert(lines, "  ╰" .. string.rep("─", CODE_WIDTH) .. "╯")
    table.insert(hl_specs, { hl = "GhReaderCode", line = #lines - 1, col_s = 0, col_e = -1 })
  end
end

-- ── section renderers ──────────────────────────────────────────────────────

local function render_comments_section(lines, hl_specs, comments)
  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  local header = "  💬 Comments (" .. #comments .. ")"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhReaderSection", line = #lines - 1, col_s = 0, col_e = #header })
  if #comments == 0 then
    local msg = "   No comments yet"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhReaderEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
    return
  end
  for _, c in ipairs(comments) do
    table.insert(lines, "")
    local meta = "  @" .. sl(c.author) .. "  ·  " .. age_string(c.created_at)
    table.insert(lines, meta)
    table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })
    table.insert(lines, "  " .. string.rep("╌", CODE_WIDTH))
    table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    process_body(c.body, lines, hl_specs)
  end
end

local function render_review_comments_section(lines, hl_specs, review_comments)
  if #review_comments == 0 then return end
  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  local header = "  🔎 Review Comments (" .. #review_comments .. ")"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhReaderSection", line = #lines - 1, col_s = 0, col_e = #header })
  for _, rc in ipairs(review_comments) do
    table.insert(lines, "")
    local meta = "  @" .. sl(rc.login) .. "  ·  " .. sl(rc.path) .. ":" .. tostring(rc.line or "?")
    table.insert(lines, meta)
    table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })
    table.insert(lines, "  " .. string.rep("╌", CODE_WIDTH))
    table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    if rc.hunk and rc.hunk ~= "" then
      local hunk_lines = {}
      for hunk_line in rc.hunk:gmatch("[^\n]+") do
        if not hunk_line:match("^@@") then table.insert(hunk_lines, hunk_line) end
      end
      local start = math.max(1, #hunk_lines - 2)
      for i = start, #hunk_lines do
        local hl      = hunk_lines[i]
        local display = "  " .. hl
        table.insert(lines, display)
        local ln = #lines - 1
        if hl:sub(1, 1) == "+" then
          table.insert(hl_specs, { hl = "GhDiffAdd", line = ln, col_s = 0, col_e = -1 })
        elseif hl:sub(1, 1) == "-" then
          table.insert(hl_specs, { hl = "GhDiffDel", line = ln, col_s = 0, col_e = -1 })
        end
      end
      table.insert(lines, "  " .. string.rep("╌", CODE_WIDTH))
      table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    end
    process_body(rc.body, lines, hl_specs)
  end
end

local function render_reviews_section(lines, hl_specs, reviews)
  local with_body = {}
  for _, r in ipairs(reviews) do
    if r.body ~= "" then table.insert(with_body, r) end
  end
  if #with_body == 0 then return end
  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  local header = "  🔍 Reviews (" .. #with_body .. ")"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhReaderSection", line = #lines - 1, col_s = 0, col_e = #header })
  for _, r in ipairs(with_body) do
    table.insert(lines, "")
    local state_icon = r.state == "APPROVED" and "✓" or (r.state == "CHANGES_REQUESTED" and "✗" or "·")
    local meta = "  " .. state_icon .. " @" .. sl(r.author) .. "  ·  " .. r.state:lower():gsub("_", " ") .. "  ·  " .. age_string(r.submitted_at)
    local hl   = r.state == "APPROVED" and "GhReviewApproved" or (r.state == "CHANGES_REQUESTED" and "GhReviewChanges" or "GhReviewComment")
    table.insert(lines, meta)
    table.insert(hl_specs, { hl = hl, line = #lines - 1, col_s = 0, col_e = -1 })
    table.insert(lines, "  " .. string.rep("╌", CODE_WIDTH))
    table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    process_body(r.body, lines, hl_specs)
  end
end

-- ── public render functions ────────────────────────────────────────────────
-- Each returns: lines, hl_specs, popup_title, popup_footer

function M.render_issue(data)
  local lines, hl_specs = {}, {}

  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb_title  = "#" .. data.number .. "  " .. sl(data.title):sub(1, 50)
  local crumb        = crumb_prefix .. crumb_title
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = #lines - 1, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = #lines - 1, col_s = #crumb_prefix, col_e = -1 })

  table.insert(lines, "")
  local title_line = "  #" .. data.number .. "  " .. sl(data.title)
  table.insert(lines, title_line)
  table.insert(hl_specs, { hl = "GhReaderTitle", line = #lines - 1, col_s = 0, col_e = -1 })

  local state_tag  = " " .. data.state .. " "
  local labels_str = #data.labels > 0 and ("  · " .. table.concat(data.labels, " · ")) or ""
  local meta       = "  " .. state_tag .. "  @" .. sl(data.author) .. labels_str .. "  ·  " .. age_string(data.created_at)
  table.insert(lines, meta)
  table.insert(hl_specs, { hl = state_hl(data.state), line = #lines - 1, col_s = 2, col_e = 2 + #state_tag })
  table.insert(hl_specs, { hl = "GhReaderMeta",       line = #lines - 1, col_s = 2 + #state_tag, col_e = -1 })

  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  table.insert(lines, "")

  process_body(data.body, lines, hl_specs)
  render_comments_section(lines, hl_specs, data.comments)

  local popup_title  = "#" .. data.number .. "  " .. sl(data.title):sub(1, 55)
  local popup_footer = "q back  ·  r refresh  ·  c comment  ·  x close issue"
  return lines, hl_specs, popup_title, popup_footer
end

function M.render_pr(data, review_comments)
  local lines, hl_specs = {}, {}

  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb_title  = "#" .. data.number .. "  " .. sl(data.title):sub(1, 50)
  local crumb        = crumb_prefix .. crumb_title
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = #lines - 1, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = #lines - 1, col_s = #crumb_prefix, col_e = -1 })

  table.insert(lines, "")
  local draft_tag  = data.is_draft and "  [draft]" or ""
  local title_line = "  #" .. data.number .. "  " .. sl(data.title) .. draft_tag
  table.insert(lines, title_line)
  table.insert(hl_specs, { hl = "GhReaderTitle", line = #lines - 1, col_s = 0, col_e = -1 })

  local state_tag = " " .. data.state .. " "
  local meta      = "  " .. state_tag .. "  @" .. sl(data.author) .. "  ·  " .. age_string(data.created_at)
  table.insert(lines, meta)
  table.insert(hl_specs, { hl = state_hl(data.state), line = #lines - 1, col_s = 2, col_e = 2 + #state_tag })
  table.insert(hl_specs, { hl = "GhReaderMeta",       line = #lines - 1, col_s = 2 + #state_tag, col_e = -1 })

  local mergeable_icon = data.mergeable == "MERGEABLE" and "✓" or (data.mergeable == "CONFLICTING" and "✗" or "?")
  local branch_line    = "  ⎇  " .. sl(data.head_ref) .. " → " .. sl(data.base_ref) .. "   merge: " .. mergeable_icon
  table.insert(lines, branch_line)
  table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })

  if #data.ci_checks > 0 then
    local parts  = { "  CI: " }
    local ci_hls = {}
    local col    = #"  CI: "
    for _, check in ipairs(data.ci_checks) do
      local s    = safe_str(check.status):upper()
      local icon = (s == "SUCCESS" or s == "COMPLETED") and "✓" or (s == "FAILURE" or s == "ERROR") and "✗" or "⠋"
      local hl   = (icon == "✓") and "GhCiPass" or (icon == "✗") and "GhCiFail" or "GhCiPending"
      local chunk = icon .. " " .. sl(check.name) .. "  "
      table.insert(ci_hls, { hl = hl, col_s = col, col_e = col + #icon })
      col = col + #chunk
      table.insert(parts, chunk)
    end
    local ci_line = table.concat(parts)
    table.insert(lines, ci_line)
    local ln = #lines - 1
    for _, h in ipairs(ci_hls) do
      table.insert(hl_specs, { hl = h.hl, line = ln, col_s = h.col_s, col_e = h.col_e })
    end
  else
    table.insert(lines, "  CI: no checks")
    table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })
  end

  if #data.reviews > 0 then
    local parts   = { "  Reviews: " }
    local rev_hls = {}
    local col     = #"  Reviews: "
    for _, r in ipairs(data.reviews) do
      local icon  = r.state == "APPROVED" and "✓" or (r.state == "CHANGES_REQUESTED" and "✗" or "·")
      local hl    = r.state == "APPROVED" and "GhReviewApproved" or (r.state == "CHANGES_REQUESTED" and "GhReviewChanges" or "GhReviewComment")
      local chunk = icon .. " " .. sl(r.author) .. "  "
      table.insert(rev_hls, { hl = hl, col_s = col, col_e = col + #icon })
      col = col + #chunk
      table.insert(parts, chunk)
    end
    local rev_line = table.concat(parts)
    table.insert(lines, rev_line)
    local ln = #lines - 1
    for _, h in ipairs(rev_hls) do
      table.insert(hl_specs, { hl = h.hl, line = ln, col_s = h.col_s, col_e = h.col_e })
    end
  else
    table.insert(lines, "  Reviews: none")
    table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })
  end

  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  table.insert(lines, "")

  process_body(data.body, lines, hl_specs)
  render_reviews_section(lines, hl_specs, data.reviews)
  render_comments_section(lines, hl_specs, data.comments)
  render_review_comments_section(lines, hl_specs, review_comments or {})

  local popup_title  = "#" .. data.number .. "  " .. sl(data.title):sub(1, 55)
  local popup_footer = "q back  ·  r refresh  ·  c comment  ·  a review  ·  d diff  ·  m merge"
  return lines, hl_specs, popup_title, popup_footer
end

function M.render_readme(data)
  local lines, hl_specs = {}, {}

  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb        = crumb_prefix .. data.full_name .. "  ›  README"
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = 0, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = 0, col_s = #crumb_prefix, col_e = -1 })
  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  table.insert(lines, "")

  process_body(data.body, lines, hl_specs)

  local popup_title  = data.full_name .. "  README"
  local popup_footer = "q back"
  return lines, hl_specs, popup_title, popup_footer
end

function M.render_diff_content(lines, hl_specs, number, repo, diff_text, err, line_map)
  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb        = crumb_prefix .. repo .. "  ›  PR #" .. number .. " diff"
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = #lines - 1, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = #lines - 1, col_s = #crumb_prefix, col_e = -1 })
  table.insert(lines, "")

  if err then
    local msg = "  ✗ " .. err:gsub("[\n\r]", " ")
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhReaderError", line = #lines - 1, col_s = 0, col_e = #msg })
    return
  end

  if diff_text == "" then
    local msg = "  (no diff)"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhReaderEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
    return
  end

  local cur_path   = nil
  local new_line_n = 0
  local old_line_n = 0

  for raw_line in diff_text:gmatch("[^\n]+") do
    table.insert(lines, raw_line)
    local buf_ln = #lines - 1

    if raw_line:match("^diff %-%-git") then
      cur_path   = raw_line:match(" b/(.+)$")
      new_line_n = 0
      old_line_n = 0
    elseif raw_line:match("^@@") then
      local ns, nn = raw_line:match("@@ %-(%d+),?%d* %+(%d+),?%d* @@")
      old_line_n = tonumber(ns or 0) - 1
      new_line_n = tonumber(nn or 0) - 1
      table.insert(hl_specs, { hl = "GhDiffHunk", line = buf_ln, col_s = 0, col_e = -1 })
    elseif raw_line:sub(1, 1) == "+" and not raw_line:match("^%+%+%+") then
      new_line_n = new_line_n + 1
      table.insert(hl_specs, { hl = "GhDiffAdd", line = buf_ln, col_s = 0, col_e = -1 })
      if line_map and cur_path then
        line_map[buf_ln] = { path = cur_path, line = new_line_n, side = "RIGHT" }
      end
    elseif raw_line:sub(1, 1) == "-" and not raw_line:match("^%-%-%-") then
      old_line_n = old_line_n + 1
      table.insert(hl_specs, { hl = "GhDiffDel", line = buf_ln, col_s = 0, col_e = -1 })
      if line_map and cur_path then
        line_map[buf_ln] = { path = cur_path, line = old_line_n, side = "LEFT" }
      end
    elseif raw_line:sub(1, 1) == " " then
      new_line_n = new_line_n + 1
      old_line_n = old_line_n + 1
      if line_map and cur_path then
        line_map[buf_ln] = { path = cur_path, line = new_line_n, side = "RIGHT" }
      end
    end
  end
end

return M
