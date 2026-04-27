local M = {}
local gh = require("gh_dashboard.gh")

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  buf  = nil,
  win  = nil,
  item = nil,
}

local ns = vim.api.nvim_create_namespace("GhRunView")

-- ── helpers ────────────────────────────────────────────────────────────────

local function sl(s) return (s or ""):gsub("[\n\r]", " ") end

local function age_string(iso8601)
  if not iso8601 then return "" end
  local y, mo, d, h, mi, s = iso8601:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t  = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  local u  = os.date("!*t", t)  u.isdst = nil
  local diff = os.time() - (t + os.difftime(t, os.time(u)))
  if     diff < 60      then return "just now"
  elseif diff < 3600    then return math.floor(diff / 60)    .. "m ago"
  elseif diff < 86400   then return math.floor(diff / 3600)  .. "h ago"
  elseif diff < 604800  then return math.floor(diff / 86400) .. "d ago"
  else                       return math.floor(diff / 604800) .. "w ago"
  end
end

local function conclusion_icon(c)
  if c == "success"                         then return "✓", "GhCiPass"
  elseif c == "failure" or c == "action_required" then return "✗", "GhCiFail"
  elseif c == "skipped"                     then return "–", "GhMeta"
  else                                           return "⠋", "GhCiPending"
  end
end

local function strip_log_timestamp(line)
  return (line:gsub("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z ", ""))
end

local function strip_log_control(line)
  return (line:gsub("^##%[%w+%]", ""))
end

-- ── buffer I/O ─────────────────────────────────────────────────────────────

local function write_buf(lines, hl_specs)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, spec.hl, spec.line,
      spec.col_s, spec.col_e == -1 and -1 or spec.col_e)
  end
end

-- ── render ─────────────────────────────────────────────────────────────────

local function render_jobs(jobs, logs_by_job_id)
  local lines    = {}
  local hl_specs = {}
  local item     = state.item

  table.insert(lines, "")

  -- Run summary header
  local c          = item.conclusion or "unknown"
  local icon, icon_hl = conclusion_icon(c)
  local summary    = "  Run: " .. sl(item.run_name or "?") .. "  ·  " .. sl(item.repo or "?")
    .. "  ·  " .. icon .. "  " .. c
  table.insert(lines, summary)
  local icon_off = #"  Run: " + #sl(item.run_name or "?") + #"  ·  " + #sl(item.repo or "?") + #"  ·  "
  table.insert(hl_specs, { hl = "GhReaderTitle", line = #lines - 1, col_s = 0,        col_e = icon_off })
  table.insert(hl_specs, { hl = icon_hl,         line = #lines - 1, col_s = icon_off, col_e = -1 })
  table.insert(lines, "")

  -- Jobs section
  local sep_line = "  " .. string.rep("─", 58)
  local jobs_hdr = "  Jobs"
  table.insert(lines, jobs_hdr)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #jobs_hdr })

  if not jobs or #jobs == 0 then
    local msg = "   No jobs found"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, job in ipairs(jobs) do
      local jicon, jhl = conclusion_icon(job.conclusion)
      local job_line = string.format("   %s  %s", jicon, sl(job.name or "?"))
      table.insert(lines, job_line)
      local jln = #lines - 1
      table.insert(hl_specs, { hl = jhl,        line = jln, col_s = 3, col_e = 3 + #jicon })
      table.insert(hl_specs, { hl = "GhItem",   line = jln, col_s = 3 + #jicon + 2, col_e = -1 })

      -- Step summary line
      local step_parts = {}
      for _, step in ipairs(job.steps or {}) do
        local sicon = conclusion_icon(step.conclusion)
        table.insert(step_parts, sicon .. " " .. sl(step.name or ""))
      end
      if #step_parts > 0 then
        local step_line = "      " .. table.concat(step_parts, "  ·  ")
        table.insert(lines, step_line)
        table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = 0, col_e = -1 })
      end
    end
  end

  -- Logs for failed jobs
  local failed_jobs = {}
  for _, job in ipairs(jobs or {}) do
    if job.conclusion == "failure" then
      table.insert(failed_jobs, job)
    end
  end

  for _, job in ipairs(failed_jobs) do
    local raw_log = logs_by_job_id and logs_by_job_id[job.id]
    table.insert(lines, "")
    table.insert(lines, sep_line)
    table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
    local log_hdr = "  Logs: " .. sl(job.name or "?")
    table.insert(lines, log_hdr)
    table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #log_hdr })

    if not raw_log then
      local msg = "   (fetching…)"
      table.insert(lines, msg)
      table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
    else
      local log_lines = vim.split(raw_log, "\n", { plain = true })
      -- keep last 150 lines
      local start = math.max(1, #log_lines - 149)
      for i = start, #log_lines do
        local raw = log_lines[i]
        local stripped = strip_log_control(strip_log_timestamp(raw))
        if stripped ~= "" then
          table.insert(lines, "  " .. stripped)
          local ln = #lines - 1
          if raw:find("^%d%d%d%d%-%d%d%-%d%dT.+##%[error%]")
            or stripped:match("^##%[error%]")
            or raw:find("##%[error%]") then
            table.insert(hl_specs, { hl = "GhCiFail", line = ln, col_s = 0, col_e = -1 })
          else
            table.insert(hl_specs, { hl = "GhStats",  line = ln, col_s = 0, col_e = -1 })
          end
        end
      end
    end
  end

  table.insert(lines, "")
  write_buf(lines, hl_specs)
end

-- ── fetch ──────────────────────────────────────────────────────────────────

local function fetch_log(repo, job_id, cb)
  vim.system(
    { "gh", "api", "repos/" .. repo .. "/actions/jobs/" .. tostring(job_id) .. "/logs" },
    { text = true },
    function(r)
      vim.schedule(function()
        cb(r.code == 0 and r.stdout or nil)
      end)
    end
  )
end

local function fetch_and_render()
  local item = state.item
  write_buf({ "", "  ⠋ loading jobs…" }, {})

  gh.run(
    { "gh", "api",
      "repos/" .. item.repo .. "/actions/runs/" .. tostring(item.run_id) .. "/jobs",
      "--jq", "[.jobs[] | {id,name,status,conclusion,steps:[.steps[]|{name,conclusion,number}]}]" },
    function(err, jobs)
      if err then
        write_buf({ "", "  ✗ " .. sl(err) }, {})
        return
      end

      -- collect failed job IDs
      local failed = {}
      for _, job in ipairs(jobs or {}) do
        if job.conclusion == "failure" then
          table.insert(failed, job)
        end
      end

      if #failed == 0 then
        render_jobs(jobs, {})
        return
      end

      -- fetch logs for each failed job then render
      local logs_by_id = {}
      local pending    = #failed

      render_jobs(jobs, nil)  -- show jobs immediately with "fetching…" placeholders

      for _, job in ipairs(failed) do
        local jid = job.id
        fetch_log(item.repo, jid, function(log_text)
          logs_by_id[jid] = log_text or "(no log data)"
          pending = pending - 1
          if pending == 0 then
            render_jobs(jobs, logs_by_id)
          end
        end)
      end
    end
  )
end

-- ── window ─────────────────────────────────────────────────────────────────

local function close_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  end
end

local function open_win()
  local title = " " .. sl(state.item.run_name or "Run") .. " "

  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.b[state.buf].render_markdown = { enabled = false }
    vim.bo[state.buf].bufhidden  = "wipe"
    vim.bo[state.buf].buftype    = "nofile"
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].filetype   = "text"
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, { title = title, title_pos = "center" })
    return
  end

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * 0.90)
  local height = math.floor(ui.height * 0.90)
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = title,
    title_pos  = "center",
    footer     = " r refresh  ·  q close ",
    footer_pos = "center",
  })

  vim.wo[state.win].number         = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn     = "no"
  vim.wo[state.win].wrap           = false
  vim.wo[state.win].cursorline     = false
  vim.wo[state.win].foldenable     = false

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end

  bmap("q",     close_win)
  bmap("<Esc>", close_win)
  bmap("r",     function() if state.item then fetch_and_render() end end)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer   = state.buf,
    once     = true,
    callback = function()
      state.buf = nil
      state.win = nil
    end,
  })
end

-- ── public API ─────────────────────────────────────────────────────────────

function M.open(item)
  state.item = item
  open_win()
  fetch_and_render()
end

return M
