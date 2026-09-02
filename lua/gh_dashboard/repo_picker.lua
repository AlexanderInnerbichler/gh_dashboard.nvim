local M = {}
local gh         = require("gh_dashboard.gh")
local highlights = require("gh_dashboard.highlights")
local config     = require("gh_dashboard.config")
local utils      = require("gh_dashboard.utils")

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  input_buf    = nil,
  input_win    = nil,
  list_buf     = nil,
  list_win     = nil,
  all_repos    = {},
  width        = 0,
  filtered_local = {},
  filtered     = {},
  gh_results   = {},
  is_searching = false,
  is_loading   = false,
}

local ns = vim.api.nvim_create_namespace("GhRepoPicker")

-- ── helpers ────────────────────────────────────────────────────────────────

local sl    = utils.sl
local trunc = utils.trunc

-- ── close ──────────────────────────────────────────────────────────────────

local function close_all()
  local iwin = state.input_win
  local lwin = state.list_win
  state.input_buf    = nil
  state.input_win    = nil
  state.list_buf     = nil
  state.list_win     = nil
  if iwin and vim.api.nvim_win_is_valid(iwin) then
    vim.api.nvim_win_close(iwin, true)
  end
  if lwin and vim.api.nvim_win_is_valid(lwin) then
    vim.api.nvim_win_close(lwin, true)
  end
end

-- ── open selected ──────────────────────────────────────────────────────────

local function open_selected()
  if not state.list_win or not vim.api.nvim_win_is_valid(state.list_win) then return end
  local cur  = vim.api.nvim_win_get_cursor(state.list_win)[1] - 1
  local repo = state.filtered[cur + 1]
  if not repo or repo.kind == "sep" then return end
  close_all()
  require("gh_dashboard.repo_view").open({ kind = "repo", full_name = repo.full_name })
end

-- ── render list ────────────────────────────────────────────────────────────

local function render_list(repos)
  if not state.list_buf or not vim.api.nvim_buf_is_valid(state.list_buf) then return end

  local lines    = {}
  local hl_specs = {}

  if #repos == 0 then
    table.insert(lines, state.is_loading and "  ⠋ loading repos…" or "   no matches")
    table.insert(hl_specs, { hl = "GhEmpty", line = 0, col_s = 0, col_e = -1 })
  else
    for _, repo in ipairs(repos) do
      if repo.kind == "sep" then
        local sep_line = state.is_searching
          and "  ⠋ searching GitHub…"
          or  "  ── GitHub Search ───────────────────────────────────────────"
        table.insert(lines, sep_line)
        local ln = #lines - 1
        table.insert(hl_specs, { hl = "GhSection", line = ln, col_s = 0, col_e = -1 })
      else
        local lang_w = 12
        local star_w = 9
        local avail  = state.width - 2 - 2 - 2 - lang_w - 2 - star_w
        local name_w = math.max(20, math.min(60, avail))

        local lock  = repo.is_private and "🔒" or " ⊙"
        local lang  = sl(repo.language or "")
        local prefix     = "  " .. lock .. "  "
        local name_field = utils.dpad(utils.dtrunc(repo.full_name, name_w), name_w)
        local lang_field = utils.dpad(utils.dtrunc(lang ~= "" and lang or "—", lang_w), lang_w)

        table.insert(lines, prefix .. name_field .. "  " .. lang_field
                            .. "  ★" .. tostring(repo.stars or 0))
        local ln   = #lines - 1
        local meta = #prefix + #name_field
        table.insert(hl_specs, { hl = "GhItem", line = ln, col_s = #prefix, col_e = meta })
        table.insert(hl_specs, { hl = "GhMeta", line = ln, col_s = meta,    col_e = -1 })
      end
    end
  end

  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.bo[state.list_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.list_buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    vim.api.nvim_buf_add_highlight(state.list_buf, ns, spec.hl, spec.line,
      spec.col_s, spec.col_e == -1 and -1 or spec.col_e)
  end
end

-- ── rebuild unified list ────────────────────────────────────────────────────

local function rebuild_filtered()
  local result = {}
  for _, r in ipairs(state.filtered_local) do table.insert(result, r) end
  if #state.gh_results > 0 or state.is_searching then
    table.insert(result, { kind = "sep" })
    for _, r in ipairs(state.gh_results) do table.insert(result, r) end
  end
  state.filtered = result
  render_list(result)
  if state.list_win and vim.api.nvim_win_is_valid(state.list_win)
    and state.list_buf and vim.api.nvim_buf_is_valid(state.list_buf)
    and vim.api.nvim_buf_line_count(state.list_buf) > 0 then
    vim.api.nvim_win_set_cursor(state.list_win, { 1, 0 })
  end
end

-- ── filter ─────────────────────────────────────────────────────────────────

local function apply_filter(query)
  query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local result = {}
  for _, repo in ipairs(state.all_repos) do
    if query == "" or repo.full_name:lower():find(query, 1, true) then
      table.insert(result, repo)
    end
  end
  state.filtered_local = result
  rebuild_filtered()
end

-- ── github search ───────────────────────────────────────────────────────────

local function search_github(query)
  if query == "" then
    state.gh_results   = {}
    state.is_searching = false
    rebuild_filtered()
    return
  end
  state.is_searching = true
  state.gh_results   = {}
  rebuild_filtered()

  gh.run_with_retry(
    { "gh", "search", "repos", query,
      "--limit", "20",
      "--json", "fullName,language,stargazersCount,isPrivate,pushedAt" },
    function(err, data)
      state.is_searching = false
      if not err then
        for _, r in ipairs(data or {}) do
          table.insert(state.gh_results, {
            full_name  = r.fullName or "",
            language   = type(r.language) == "string" and r.language or "",
            stars      = r.stargazersCount or 0,
            is_private = r.isPrivate,
            updated_at = r.pushedAt,
            source     = "gh",
          })
        end
      end
      rebuild_filtered()
    end
  )
end

-- ── fetch all repos ────────────────────────────────────────────────────────

local function fetch_repos()
  state.is_loading = true
  if state.list_buf and vim.api.nvim_buf_is_valid(state.list_buf) then
    vim.bo[state.list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, { "  ⠋ loading repos…" })
    vim.bo[state.list_buf].modifiable = false
  end

  local all     = {}
  local seen    = {}
  local pending = 2

  local function done()
    pending = pending - 1
    if pending ~= 0 then return end
    state.is_loading = false
    table.sort(all, function(a, b) return (a.updated_at or "") > (b.updated_at or "") end)
    state.all_repos = all
    apply_filter("")
  end

  gh.run_with_retry(
    { "gh", "repo", "list", "--limit", "1000",
      "--json", "nameWithOwner,primaryLanguage,stargazerCount,isPrivate,pushedAt" },
    function(err, data)
      for _, r in ipairs(data or {}) do
        local fn = r.nameWithOwner
        if not seen[fn] then
          seen[fn] = true
          table.insert(all, {
            full_name  = fn,
            language   = type(r.primaryLanguage) == "table" and r.primaryLanguage.name or "",
            stars      = r.stargazerCount or 0,
            is_private = r.isPrivate,
            updated_at = r.pushedAt,
          })
        end
      end
      done()
    end
  )

  require("gh_dashboard.dashboard.fetch").org_repos(function(err, repos)
    for _, r in ipairs(repos or {}) do
      if not seen[r.full_name] then
        seen[r.full_name] = true
        table.insert(all, r)
      end
    end
    done()
  end)
end

-- ── windows ────────────────────────────────────────────────────────────────

local function open_windows()
  local ui       = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width    = math.floor(ui.width * config.get().window_width)
  local list_h   = math.floor(ui.height * 0.72)
  state.width    = width
  local input_h  = 1
  local total_h  = input_h + 2 + 1 + list_h
  local start_row = math.floor((ui.height - total_h) / 2)
  local col      = math.floor((ui.width - width) / 2)

  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.b[state.input_buf].render_markdown = { enabled = false }
  vim.bo[state.input_buf].buftype    = "nofile"
  vim.bo[state.input_buf].bufhidden  = "wipe"
  vim.bo[state.input_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
    relative   = "editor",
    width      = width,
    height     = input_h,
    row        = start_row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " Search Repos   type to filter   <CR> search GitHub   <Tab> list   <Esc> close ",
    title_pos  = "center",
  })
  vim.wo[state.input_win].number         = false
  vim.wo[state.input_win].relativenumber = false
  vim.wo[state.input_win].signcolumn     = "no"
  vim.wo[state.input_win].cursorline     = false
  vim.wo[state.input_win].foldenable     = false
  vim.cmd("startinsert")

  state.list_buf = vim.api.nvim_create_buf(false, true)
  vim.b[state.list_buf].render_markdown = { enabled = false }
  vim.bo[state.list_buf].buftype    = "nofile"
  vim.bo[state.list_buf].bufhidden  = "wipe"
  vim.bo[state.list_buf].modifiable = false

  local list_row = start_row + input_h + 3
  state.list_win = vim.api.nvim_open_win(state.list_buf, false, {
    relative   = "editor",
    width      = width,
    height     = list_h,
    row        = list_row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " Results ",
    title_pos  = "left",
    footer     = " <CR> open   <Tab> back to search   q / <Esc> close ",
    footer_pos = "center",
  })
  vim.wo[state.list_win].number         = false
  vim.wo[state.list_win].relativenumber = false
  vim.wo[state.list_win].signcolumn     = "no"
  vim.wo[state.list_win].cursorline     = true
  vim.wo[state.list_win].wrap           = false
  vim.wo[state.list_win].foldenable     = false

  -- ── keymaps ──

  local function imap(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = state.input_buf, nowait = true, silent = true })
  end
  local function lmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.list_buf, nowait = true, silent = true })
  end

  -- live filter on every keystroke
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer   = state.input_buf,
    callback = function()
      local q = (vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)[1] or "")
      apply_filter(q)
    end,
  })

  -- <CR>: empty query → open first local match; non-empty → search GitHub
  imap("i", "<CR>", function()
    local q = (vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)[1] or "")
      :gsub("^%s+", ""):gsub("%s+$", "")
    if q == "" then
      if #state.filtered_local > 0 then
        local repo = state.filtered_local[1]
        close_all()
        require("gh_dashboard.repo_view").open({ kind = "repo", full_name = repo.full_name })
      end
    else
      vim.cmd("stopinsert")
      search_github(q)
      vim.cmd("startinsert!")
    end
  end)

  -- <Tab> / <C-n> / <Down> → focus list
  local function focus_list()
    vim.cmd("stopinsert")
    if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
      vim.api.nvim_set_current_win(state.list_win)
    end
  end
  imap("i", "<Tab>",  focus_list)
  imap("i", "<C-n>",  focus_list)
  imap("i", "<Down>", focus_list)

  -- close from either mode; the picker opens in insert, where "q" is a literal
  imap("i", "<Esc>",  close_all)
  imap("i", "<C-c>",  close_all)
  imap("n", "<Esc>",  close_all)
  imap("n", "<C-c>",  close_all)
  imap("n", "q",      close_all)

  -- list: <CR> / o → open selected (skips separator)
  lmap("<CR>", open_selected)
  lmap("o",    open_selected)

  -- list: <Tab> / i → back to input
  local function focus_input()
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
      vim.api.nvim_set_current_win(state.input_win)
      vim.cmd("startinsert!")
    end
  end
  lmap("<Tab>", focus_input)
  lmap("i",     focus_input)

  -- list: q / <Esc> → close
  lmap("q",     close_all)
  lmap("<Esc>", close_all)

  local function on_wipeout()
    state.input_buf    = nil
    state.input_win    = nil
    state.list_buf     = nil
    state.list_win     = nil
    state.all_repos    = {}
    state.filtered_local = {}
    state.filtered     = {}
    state.gh_results   = {}
    state.is_searching = false
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.input_buf, once = true, callback = on_wipeout,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.list_buf, once = true, callback = on_wipeout,
  })
end

-- ── public API ─────────────────────────────────────────────────────────────

M.open = function()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    close_all()
    return
  end
  highlights.setup()
  open_windows()
  fetch_repos()
end

return M
