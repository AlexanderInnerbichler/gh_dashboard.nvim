local M          = {}
local config     = require("gh_dashboard.config")
local utils      = require("gh_dashboard.utils")
local highlights = require("gh_dashboard.highlights")
local fetch      = require("gh_dashboard.diff.fetch")
local patch      = require("gh_dashboard.diff.patch")
local panel      = require("gh_dashboard.diff.panel")
local view       = require("gh_dashboard.diff.view")
local review     = require("gh_dashboard.diff.review")

local ns_panel = vim.api.nvim_create_namespace("GhDiffPanel")
local ns_base  = vim.api.nvim_create_namespace("GhDiffBaseComments")
local ns_head  = vim.api.nvim_create_namespace("GhDiffHeadComments")

local VIEWED_PATH = vim.fn.expand("~/.cache/nvim/gh-dashboard-viewed.json")

-- ── state ──────────────────────────────────────────────────────────────────

local state = {}

local function reset_state()
  state = {
    tab            = nil,
    picker_win     = nil, panel_buf = nil,
    picker_width   = 0,
    base_win       = nil, base_buf  = nil,
    head_win       = nil, head_buf  = nil,
    item           = nil,
    meta           = nil,
    files          = {},
    visible        = {},
    index          = 0,
    viewed         = {},
    layout         = "side_by_side",
    sort           = "path",
    filter         = "",
    hide_generated = true,
    skip_whitespace = false,
    comments       = {},
    line_of_index  = {},
    row_map        = {},
    hunks          = {},
    ranges         = {},
    line_map       = {},
    hunk_lines     = {},
    marked         = { base = {}, head = {} },
    blob_cache     = {},
    req            = 0,
    syncing        = false,
    timer          = nil,
    saved_diffopt  = nil,
  }
end

reset_state()

local function opts() return config.get().diff end

--- vim.defer_fn only closes its timer when it fires, so a superseded one has to
--- be closed by hand or it leaks a libuv handle per cursor move.
local function cancel_preview()
  if state.timer and not state.timer:is_closing() then state.timer:close() end
  state.timer = nil
end

-- ── diffopt ────────────────────────────────────────────────────────────────

--- diffopt is global, so rebuild it from the value we captured on open rather
--- than appending, and restore that value when the tab closes.
local function apply_diffopt()
  if not state.saved_diffopt then return end
  local parts = {}
  for _, p in ipairs(vim.split(state.saved_diffopt, ",", { plain = true })) do
    if not p:match("^context:") and not p:match("^iwhite") then
      table.insert(parts, p)
    end
  end
  table.insert(parts, "context:" .. opts().context)
  if state.skip_whitespace then table.insert(parts, "iwhiteall") end
  vim.o.diffopt = table.concat(parts, ",")
  for _, win in ipairs({ state.base_win, state.head_win }) do
    if win and vim.api.nvim_win_is_valid(win) and vim.wo[win].diff then
      vim.api.nvim_win_call(win, function() vim.cmd("diffupdate") end)
      break
    end
  end
end

local function restore_diffopt()
  if state.saved_diffopt then
    vim.o.diffopt = state.saved_diffopt
    state.saved_diffopt = nil
  end
end

-- ── viewed-state persistence ───────────────────────────────────────────────

local function viewed_key()
  return string.format("%s#%d@%s", state.item.repo, state.item.number,
                       (state.meta and state.meta.head_sha or ""):sub(1, 12))
end

local function read_viewed_store()
  local fd = io.open(VIEWED_PATH, "r")
  if not fd then return {} end
  local raw = fd:read("*a")
  fd:close()
  local ok, data = pcall(vim.json.decode, raw)
  return (ok and type(data) == "table") and data or {}
end

local function load_viewed()
  local store = read_viewed_store()
  local entry = store[viewed_key()]
  state.viewed = type(entry) == "table" and entry or {}
end

local function save_viewed()
  local store = read_viewed_store()
  local key   = viewed_key()
  -- prune before inserting, and never evict the entry we are about to write
  local keys = vim.tbl_keys(store)
  for i = 1, #keys - 50 do
    if keys[i] ~= key then store[keys[i]] = nil end
  end
  store[key] = state.viewed
  vim.fn.mkdir(vim.fn.fnamemodify(VIEWED_PATH, ":h"), "p")
  local fd = io.open(VIEWED_PATH, "w")
  if not fd then return end
  fd:write(vim.json.encode(store))
  fd:close()
end

-- ── layout ─────────────────────────────────────────────────────────────────

local function is_open()
  return state.tab and vim.api.nvim_tabpage_is_valid(state.tab)
end

local function diff_wins()
  local wins = {}
  if state.base_win and vim.api.nvim_win_is_valid(state.base_win) then
    table.insert(wins, state.base_win)
  end
  if state.head_win and vim.api.nvim_win_is_valid(state.head_win) then
    table.insert(wins, state.head_win)
  end
  return wins
end

local function size_windows()
  local wins = diff_wins()
  if #wins == 2 then
    vim.api.nvim_win_set_width(wins[1], math.floor((vim.o.columns - 1) / 2))
  end
end

local function build_layout()
  vim.cmd("tabnew")
  -- tabnew hands us an empty buffer we immediately replace; drop it so the
  -- buffer list doesn't collect one [No Name] per open.
  local scratch  = vim.api.nvim_get_current_buf()
  state.tab      = vim.api.nvim_get_current_tabpage()
  state.base_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.base_win, state.base_buf)
  if vim.api.nvim_buf_is_valid(scratch) and vim.api.nvim_buf_get_name(scratch) == "" then
    pcall(vim.api.nvim_buf_delete, scratch, { force = true })
  end

  vim.cmd("vertical rightbelow split")
  state.head_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.head_win, state.head_buf)

  size_windows()
end

--- Add or drop the base window so the window count matches the current layout.
local function apply_layout()
  if state.layout == "unified" then
    if state.base_win and vim.api.nvim_win_is_valid(state.base_win) then
      view.disable_diff({ state.base_win, state.head_win })
      vim.api.nvim_win_close(state.base_win, true)
      state.base_win = nil
    end
    if state.head_win and vim.api.nvim_win_is_valid(state.head_win) then
      vim.wo[state.head_win].wrap   = false
      vim.wo[state.head_win].number = false
    end
  elseif not (state.base_win and vim.api.nvim_win_is_valid(state.base_win)) then
    vim.api.nvim_set_current_win(state.head_win)
    vim.cmd("vertical leftabove split")
    state.base_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.base_win, state.base_buf)
  end
  size_windows()
end

-- ── file picker ────────────────────────────────────────────────────────────

local function picker_open()
  return state.picker_win and vim.api.nvim_win_is_valid(state.picker_win)
end

local function picker_title()
  local viewed_n = 0
  for _, f in ipairs(state.files) do
    if state.viewed[f.path] then viewed_n = viewed_n + 1 end
  end
  return string.format(" PR #%d   %s   %d/%d viewed ",
    state.item.number, state.item.repo, viewed_n, #state.files)
end

local function close_picker()
  if picker_open() then vim.api.nvim_win_close(state.picker_win, true) end
  state.picker_win = nil
end

-- ── panel rendering ────────────────────────────────────────────────────────

local function comments_by_path()
  local by = {}
  for _, c in ipairs(state.comments) do
    if c.path and not c.outdated then
      by[c.path] = by[c.path] or {}
      table.insert(by[c.path], c)
    end
  end
  for _, c in ipairs(review.all()) do
    by[c.path] = by[c.path] or {}
    table.insert(by[c.path], c)
  end
  return by
end

local function outdated_comments()
  local out = {}
  for _, c in ipairs(state.comments) do
    if c.outdated then table.insert(out, c) end
  end
  return out
end

local function render_panel()
  local lines, hl_specs, row_map = panel.render({
    number           = state.item.number,
    repo             = state.item.repo,
    width            = state.picker_width,
    files            = state.files,
    visible          = state.visible,
    viewed           = state.viewed,
    pending          = review.all(),
    filter           = state.filter,
    sort             = state.sort,
    hide_generated   = state.hide_generated,
    skip_whitespace  = state.skip_whitespace,
    comments_by_path = comments_by_path(),
    outdated         = outdated_comments(),
  })
  utils.write_buf(state.panel_buf, ns_panel, lines, hl_specs)

  state.row_map       = row_map
  state.line_of_index = {}
  for ln, idx in pairs(row_map) do
    if not state.line_of_index[idx] or ln < state.line_of_index[idx] then
      state.line_of_index[idx] = ln
    end
  end

  if picker_open() then
    pcall(vim.api.nvim_win_set_config, state.picker_win, { title = picker_title() })
  end

  local target = state.line_of_index[state.index]
  if target and picker_open() then
    state.syncing = true
    pcall(vim.api.nvim_win_set_cursor, state.picker_win, { target + 1, 0 })
    vim.schedule(function() state.syncing = false end)
  end
end

--- The keys worth knowing, longest set that fits. A split layout has no
--- floating-window footer, so the winbar is the only pinned place for them.
local HINT_TIERS = {
  "q files  <Tab> next  ]h hunk  <Spc> viewed  c comment  A submit  x unified  ? help",
  "q files  <Tab> next  ]h hunk  <Spc> viewed  c comment  A submit  ? help",
  "q files  <Tab> next  ]h hunk  <Spc> viewed  c comment  ? help",
  "q files  <Tab> next  <Spc> viewed  c comment  ? help",
  "q files  <Spc> viewed  c comment  ? help",
  "q files  ? help",
}

local function hints_for(avail)
  for _, tier in ipairs(HINT_TIERS) do
    if vim.fn.strdisplaywidth(tier) <= avail then return tier end
  end
  return ""
end

--- Per-window headers. winbar rather than statusline, because a window-local
--- statusline never renders under laststatus=3.
--- The file list, as a modal picker over the diff rather than a fixed column.
--- Leaves the diff the full width of the terminal.
local function open_picker()
  if picker_open() then
    vim.api.nvim_set_current_win(state.picker_win)
    return
  end
  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.max(40, math.min(110, math.floor(ui.width * opts().picker_width)))
  local height = math.max(8, math.min(math.floor(ui.height * 0.8), #state.visible * 2 + 12))
  state.picker_width = width

  state.picker_win = vim.api.nvim_open_win(state.panel_buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = math.floor((ui.height - height) / 2) - 1,
    col        = math.floor((ui.width - width) / 2),
    style      = "minimal",
    border     = "rounded",
    title      = picker_title(),
    title_pos  = "center",
    footer     = " <CR> open   <Space> viewed   S sort   f filter   q close ",
    footer_pos = "center",
  })
  vim.wo[state.picker_win].number         = false
  vim.wo[state.picker_win].relativenumber = false
  vim.wo[state.picker_win].signcolumn     = "no"
  vim.wo[state.picker_win].wrap           = false
  vim.wo[state.picker_win].cursorline     = true
  vim.wo[state.picker_win].foldenable     = false
  vim.wo[state.picker_win].list           = false
  render_panel()
end

local function set_titles(f)
  if not is_open() then return end
  if not (state.head_win and vim.api.nvim_win_is_valid(state.head_win)) then return end

  local raw = f and f.path or "no file"
  if f and f.prev then raw = f.prev .. " → " .. f.path end

  -- "head" / "unified" was redundant (one pane vs two says it), so the right
  -- side of this winbar is free for the key hints.
  local avail = vim.api.nvim_win_get_width(state.head_win)
                - vim.fn.strdisplaywidth(raw) - 4
  vim.wo[state.head_win].winbar = "%#GhDiffWinbar# " .. raw:gsub("%%", "%%%%")
    .. " %#GhDiffWinbarDim#%=" .. hints_for(avail) .. " "

  if state.base_win and vim.api.nvim_win_is_valid(state.base_win) then
    local base_ref = state.meta and state.meta.base_ref or ""
    vim.wo[state.base_win].winbar = "%#GhDiffWinbarDim# base" ..
      (base_ref ~= "" and ("  " .. base_ref:gsub("%%", "%%%%")) or "") .. "%="
  end
end

-- ── comment overlays ───────────────────────────────────────────────────────

local function entries_for(path, side)
  local out = {}
  for _, c in ipairs(state.comments) do
    if c.path == path and not c.outdated and (c.side or "RIGHT") == side then
      table.insert(out, c)
    end
  end
  for _, c in ipairs(review.for_path(path)) do
    if c.side == side then
      table.insert(out, vim.tbl_extend("force", c, { pending = true }))
    end
  end
  return out
end

local function draw_comments(f)
  if not (state.head_win and vim.api.nvim_win_is_valid(state.head_win)) then return end
  local width = math.max(30, vim.api.nvim_win_get_width(state.head_win))
  if state.layout == "unified" then
    local remapped = {}
    for _, c in ipairs(vim.list_extend(entries_for(f.path, "RIGHT"), entries_for(f.path, "LEFT"))) do
      for buf_ln, info in pairs(state.line_map) do
        if info.line == c.line and info.side == (c.side or "RIGHT") then
          table.insert(remapped, vim.tbl_extend("force", c, { line = buf_ln + 1 }))
          break
        end
      end
    end
    state.marked.head = view.overlay_comments(state.head_buf, ns_head, remapped, width)
    state.marked.base = {}
  else
    state.marked.head = view.overlay_comments(state.head_buf, ns_head, entries_for(f.path, "RIGHT"), width)
    if state.base_buf then
      state.marked.base = view.overlay_comments(state.base_buf, ns_base, entries_for(f.path, "LEFT"), width)
    end
  end
end

-- ── file loading ───────────────────────────────────────────────────────────

local function prefetch(idx)
  local f = state.visible[idx]
  if not f or not f.patch or state.blob_cache[f.path] then return end
  if f.status == "added" or f.status == "removed" then return end
  fetch.fetch_blob(state.item.repo, f.path, state.meta.head_sha, function(err, lines)
    if not err then state.blob_cache[f.path] = lines end
  end)
end

local function show_unified(f)
  local lines, hl_specs, line_map, hunk_lines =
    patch.render_unified(state.hunks, state.skip_whitespace)
  state.line_map, state.hunk_lines = line_map, hunk_lines
  view.disable_diff({ state.head_win })
  utils.write_buf(state.head_buf, ns_head, lines, hl_specs)
  vim.bo[state.head_buf].filetype = "diff"
  draw_comments(f)
end

local function show_side_by_side(f, base_lines, head_lines)
  view.set_content(state.base_buf, base_lines, f.prev or f.path)
  view.set_content(state.head_buf, head_lines, f.path)
  view.enable_diff(diff_wins())
  draw_comments(f)
  if vim.api.nvim_win_is_valid(state.head_win) and #state.hunks > 0 then
    local target = math.min(math.max(patch.first_change_line(state.hunks), 1),
                            vim.api.nvim_buf_line_count(state.head_buf))
    pcall(vim.api.nvim_win_set_cursor, state.head_win, { target, 0 })
    vim.api.nvim_win_call(state.head_win, function() vim.cmd("normal! zv") end)
  end
end

local function show_message(text)
  view.disable_diff(diff_wins())
  utils.write_buf(state.head_buf, ns_head, view.placeholder(text), {})
  if state.base_buf then utils.write_buf(state.base_buf, ns_base, { "" }, {}) end
end

local function open_file(idx)
  if not is_open() then return end
  if idx < 1 or idx > #state.visible then return end
  state.index = idx
  local f = state.visible[idx]

  state.hunks  = f.patch and patch.parse(f.patch) or {}
  state.ranges = patch.comment_ranges(state.hunks)
  render_panel()
  set_titles(f)

  state.req = state.req + 1
  local token = state.req

  if not f.patch then
    show_message(f.status == "renamed"
      and ("renamed from " .. (f.prev or "?") .. " — no content changes")
      or  "no patch available for this file (binary, or too large for the API)")
    return
  end

  if state.layout == "unified" then
    show_unified(f)
    prefetch(idx + 1)
    return
  end

  local function render(base_lines, head_lines)
    if token ~= state.req or not is_open() then return end
    show_side_by_side(f, base_lines, head_lines)
    prefetch(idx + 1)
  end

  if f.status == "added" then
    render({}, patch.side_lines(state.hunks, "new"))
  elseif f.status == "removed" then
    render(patch.side_lines(state.hunks, "old"), {})
  elseif state.blob_cache[f.path] then
    local head_lines = state.blob_cache[f.path]
    render(patch.reconstruct_base(head_lines, state.hunks), head_lines)
  else
    show_message("loading " .. f.path .. "…")
    fetch.fetch_blob(state.item.repo, f.path, state.meta.head_sha, function(err, head_lines)
      if token ~= state.req or not is_open() then return end
      if err or #head_lines == 0 then
        show_unified(f)
        return
      end
      state.blob_cache[f.path] = head_lines
      render(patch.reconstruct_base(head_lines, state.hunks), head_lines)
    end)
  end
end

-- ── navigation ─────────────────────────────────────────────────────────────

local function goto_file(delta)
  local next_idx = state.index + delta
  if next_idx < 1 or next_idx > #state.visible then
    vim.notify(delta > 0 and "Last file" or "First file", vim.log.levels.INFO)
    return
  end
  open_file(next_idx)
end

local function goto_unviewed()
  for i = state.index + 1, #state.visible do
    if not state.viewed[state.visible[i].path] then open_file(i) return end
  end
  for i = 1, state.index do
    if not state.viewed[state.visible[i].path] then open_file(i) return end
  end
  vim.notify("All files viewed", vim.log.levels.INFO)
end

local function goto_hunk(delta)
  if state.layout == "unified" then
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local targets = state.hunk_lines
    if delta > 0 then
      for _, ln in ipairs(targets) do
        if ln > cur then pcall(vim.api.nvim_win_set_cursor, 0, { ln, 0 }) return end
      end
    else
      for i = #targets, 1, -1 do
        if targets[i] < cur then pcall(vim.api.nvim_win_set_cursor, 0, { targets[i], 0 }) return end
      end
    end
    goto_file(delta)
  else
    local before = vim.api.nvim_win_get_cursor(0)[1]
    pcall(vim.cmd, "normal! " .. (delta > 0 and "]c" or "[c"))
    if vim.api.nvim_win_get_cursor(0)[1] == before then goto_file(delta) end
  end
end

local function goto_comment(delta)
  local win = vim.api.nvim_get_current_win()
  local marks = win == state.base_win and state.marked.base or state.marked.head
  local cur   = vim.api.nvim_win_get_cursor(0)[1]
  if delta > 0 then
    for _, ln in ipairs(marks) do
      if ln > cur then pcall(vim.api.nvim_win_set_cursor, 0, { ln, 0 }) return end
    end
  else
    for i = #marks, 1, -1 do
      if marks[i] < cur then pcall(vim.api.nvim_win_set_cursor, 0, { marks[i], 0 }) return end
    end
  end
  vim.notify("No more comments in this file", vim.log.levels.INFO)
end

-- ── file list refiltering ──────────────────────────────────────────────────

local function refilter(keep_path)
  keep_path = keep_path or (state.visible[state.index] and state.visible[state.index].path)
  state.visible = panel.arrange(state.files, {
    filter          = state.filter,
    sort            = state.sort,
    hide_generated  = state.hide_generated,
    generated_globs = opts().generated_globs,
  })
  state.index = 1
  for i, f in ipairs(state.visible) do
    if f.path == keep_path then state.index = i break end
  end
  if #state.visible == 0 then
    state.index = 0
    render_panel()
    show_message("no files match the current filter")
  else
    open_file(state.index)
  end
end

-- ── actions ────────────────────────────────────────────────────────────────

local function toggle_viewed()
  local f = state.visible[state.index]
  if not f then return end
  state.viewed[f.path] = (not state.viewed[f.path]) or nil
  save_viewed()
  if state.viewed[f.path] then goto_unviewed() else render_panel() end
end

local function comment_target(mode)
  local win = vim.api.nvim_get_current_win()
  local f   = state.visible[state.index]
  if not f or win == state.picker_win then return nil end

  local from, to
  if mode == "visual" then
    vim.cmd("normal! \27")
    from = vim.fn.getpos("'<")[2]
    to   = vim.fn.getpos("'>")[2]
  else
    from = vim.api.nvim_win_get_cursor(0)[1]
    to   = from
  end

  local function resolve(buf_line)
    if state.layout == "unified" then
      return state.line_map[buf_line - 1]
    end
    return { line = buf_line, side = win == state.base_win and "LEFT" or "RIGHT" }
  end

  local a, b = resolve(from), resolve(to)
  if not b then return nil end
  if not patch.in_ranges(state.ranges[b.side], b.line) then return nil end

  local target = { path = f.path, line = b.line, side = b.side }
  if a and a ~= b and a.side == b.side and patch.in_ranges(state.ranges[a.side], a.line) then
    target.start_line = a.line
    target.start_side = a.side
  end
  return target
end

local function add_comment(mode)
  local target = comment_target(mode)
  if not target then
    vim.notify(vim.api.nvim_get_current_win() == state.picker_win
      and "Open a file first, then comment on a changed line"
      or  "That line is not part of the diff — comment on a changed line",
      vim.log.levels.INFO)
    return
  end
  vim.schedule(function()
    utils.prompt({ title = "Review comment", lines = 12,
                   footer = " <C-s> queue   <Esc> then <Esc> cancel" }, function(body)
      if body == "" then return end
      review.add(vim.tbl_extend("force", target, { body = body, login = "you" }))
      local f = state.visible[state.index]
      if f then draw_comments(f) end
      render_panel()
      vim.notify(string.format("Queued (%d pending) — press A to submit", #review.all()),
                 vim.log.levels.INFO)
    end)
  end)
end

local function submit_review()
  local pending = review.all()
  vim.ui.select(
    { "Comment", "Approve", "Request Changes", "Cancel" },
    { prompt = string.format("Submit review with %d inline comment%s:",
                             #pending, #pending == 1 and "" or "s") },
    function(choice)
      if not choice or choice == "Cancel" then return end
      local event = choice == "Approve" and "APPROVE"
                 or choice == "Request Changes" and "REQUEST_CHANGES"
                 or "COMMENT"
      utils.prompt({ title = choice .. " — summary", lines = 12 }, function(body)
        if event == "COMMENT" and body == "" and #pending == 0 then
          vim.notify("Nothing to submit", vim.log.levels.WARN)
          return
        end
        review.submit(state.item.number, state.item.repo, state.meta.head_sha,
                      event, body, function(err)
          if err then
            vim.notify("Review failed: " .. err, vim.log.levels.ERROR)
            return
          end
          vim.notify("Review submitted", vim.log.levels.INFO)
          fetch.fetch_review_comments(state.item.number, state.item.repo, function(list)
            state.comments = list
            render_panel()
            local f = state.visible[state.index]
            if f then draw_comments(f) end
          end)
        end)
      end)
    end
  )
end

local function web_url(with_line)
  local f = state.visible[state.index]
  if not f then return nil end
  local base = string.format("https://github.com/%s/pull/%d/files",
                             state.item.repo, state.item.number)
  local anchor = vim.fn.sha256(f.path):sub(1, 64)
  if with_line and state.meta then
    return string.format("https://github.com/%s/blob/%s/%s#L%d",
      state.item.repo, state.meta.head_sha, f.path,
      vim.api.nvim_win_get_cursor(0)[1])
  end
  return base .. "#diff-" .. anchor
end

-- ── keymaps ────────────────────────────────────────────────────────────────

local function bufs()
  local list = { state.panel_buf, state.head_buf }
  if state.base_buf then table.insert(list, state.base_buf) end
  return list
end

local function map_all(lhs, fn, mode)
  for _, buf in ipairs(bufs()) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.keymap.set(mode or "n", lhs, fn, { buffer = buf, nowait = true, silent = true })
    end
  end
end

--- File-list options live on the panel only, so f/F/S/w stay native motions in
--- the diff windows, where you are reading code.
local function map_panel(lhs, fn)
  if state.panel_buf and vim.api.nvim_buf_is_valid(state.panel_buf) then
    vim.keymap.set("n", lhs, fn, { buffer = state.panel_buf, nowait = true, silent = true })
  end
end

local function focus(win)
  if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
end

local function register_keymaps()
  map_all("q",         function() open_picker() end)
  map_all("<Tab>",     function() goto_file(1) end)
  map_all("<S-Tab>",   function() goto_file(-1) end)
  map_all("]f",        function() goto_file(1) end)
  map_all("[f",        function() goto_file(-1) end)
  map_all("]h",        function() goto_hunk(1) end)
  map_all("[h",        function() goto_hunk(-1) end)
  map_all("]x",        function() goto_comment(1) end)
  map_all("[x",        function() goto_comment(-1) end)
  map_all("u",         goto_unviewed)
  map_all("<Space>",   toggle_viewed)
  map_all("c",         function() add_comment("normal") end)
  map_all("c",         function() add_comment("visual") end, "x")
  map_all("A",         submit_review)
  map_all("D", function()
    if #review.all() == 0 then
      vim.notify("No pending comments", vim.log.levels.INFO)
      return
    end
    vim.ui.input({ prompt = "Discard " .. #review.all() .. " pending comment(s)? (yes/no): " },
      function(ans)
        if ans ~= "yes" then return end
        review.clear()
        render_panel()
        local f = state.visible[state.index]
        if f then draw_comments(f) end
      end)
  end)
  map_all("x", function()
    state.layout = state.layout == "unified" and "side_by_side" or "unified"
    apply_layout()
    register_keymaps()
    open_file(state.index)
    focus(state.head_win)
  end)
  map_panel("S", function()
    local order = panel.SORT_ORDER
    local at = 1
    for i, s in ipairs(order) do if s == state.sort then at = i end end
    state.sort = order[at % #order + 1]
    refilter()
  end)
  map_panel("f", function()
    vim.ui.input({ prompt = "Filter files: ", default = state.filter }, function(input)
      if input == nil then return end
      state.filter = input
      refilter()
    end)
  end)
  map_panel("F", function()
    state.hide_generated = not state.hide_generated
    refilter()
  end)
  map_panel("w", function()
    state.skip_whitespace = not state.skip_whitespace
    if state.layout == "unified" then
      open_file(state.index)
    else
      apply_diffopt()
      render_panel()
    end
    vim.notify("Whitespace-only changes " .. (state.skip_whitespace and "hidden" or "shown"),
               vim.log.levels.INFO)
  end)
  map_all("r", function() M.open(state.item) end)
  map_all("O", function()
    local url = web_url(false)
    if url then utils.open_url(url) end
  end)
  map_all("gy", function()
    local url = web_url(true)
    if not url then return end
    vim.fn.setreg("+", url)
    vim.fn.setreg('"', url)
    vim.notify("Copied " .. url, vim.log.levels.INFO)
  end)
  map_all("<C-h>", function() open_picker() end)
  map_all("<C-l>", function() focus(state.head_win) end)

  for _, buf in ipairs(bufs()) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      require("gh_dashboard.help").setup_keymap(buf, "diff")
    end
  end

  local function pmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.panel_buf, nowait = true, silent = true })
  end
  local function enter_diff()
    if not picker_open() then return end
    local idx = state.row_map[vim.api.nvim_win_get_cursor(state.picker_win)[1] - 1]
    if not idx then return end
    open_file(idx)
    close_picker()
    focus(state.head_win)
  end
  pmap("<CR>", enter_diff)
  pmap("o",    enter_diff)
  pmap("q",     function() M.close() end)
  pmap("<Esc>", function() M.close() end)
end

-- ── auto preview ───────────────────────────────────────────────────────────

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("GhDiffView", { clear = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group  = group,
    buffer = state.panel_buf,
    callback = function()
      if state.syncing or not opts().auto_preview or not picker_open() then return end
      local ln  = vim.api.nvim_win_get_cursor(state.picker_win)[1] - 1
      local idx = state.row_map[ln]
      if not idx or idx == state.index then return end
      cancel_preview()
      state.timer = vim.defer_fn(function()
        if is_open() and picker_open()
          and state.row_map[vim.api.nvim_win_get_cursor(state.picker_win)[1] - 1] == idx then
          open_file(idx)
        end
      end, 90)
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group    = group,
    callback = function()
      if not is_open() then return end
      size_windows()
      set_titles(state.visible[state.index])
    end,
  })

  vim.api.nvim_create_autocmd("TabClosed", {
    group    = group,
    callback = function()
      if state.tab and not vim.api.nvim_tabpage_is_valid(state.tab) then
        restore_diffopt()
        state.tab = nil
      end
    end,
  })
end

-- ── public API ─────────────────────────────────────────────────────────────

function M.close()
  cancel_preview()
  close_picker()
  restore_diffopt()
  if is_open() then
    local tab = state.tab
    state.tab = nil
    pcall(vim.api.nvim_set_current_tabpage, tab)
    pcall(vim.cmd, "tabclose")
  end
  for _, buf in ipairs({ state.panel_buf, state.base_buf, state.head_buf }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  reset_state()
  pcall(function() require("gh_dashboard").focus_win() end)
end

function M.open(item)
  highlights.setup()
  view.setup_diff_hl()

  local was_open = is_open()
  local keep     = was_open and state.visible[state.index] and state.visible[state.index].path or nil
  local layout   = was_open and state.layout or opts().layout
  local viewed_cache = was_open and state.viewed or nil

  if was_open then M.close() end

  reset_state()
  state.item           = item
  state.layout         = layout
  state.hide_generated = opts().hide_generated
  state.viewed         = viewed_cache or {}
  review.reset(item.repo .. "#" .. item.number)

  local tag = "GhDiff-" .. item.number
  state.panel_buf = view.new_buf(tag)
  state.base_buf  = view.new_buf(tag .. ":base")
  state.head_buf  = view.new_buf(tag .. ":head")

  state.saved_diffopt = vim.o.diffopt
  apply_diffopt()

  build_layout()
  if state.layout == "unified" then apply_layout() end
  register_keymaps()
  setup_autocmds()

  state.picker_width = 60
  utils.write_buf(state.panel_buf, ns_panel,
    { "", "  ⠋ loading changed files…" }, {})
  open_picker()
  utils.write_buf(state.head_buf, ns_head, { "", "  Loading diff…" }, {})

  local pending = 2
  local files_err

  local function ready()
    pending = pending - 1
    if pending > 0 or not is_open() then return end
    if files_err then
      utils.write_buf(state.panel_buf, ns_panel, { "", "  ✗ " .. utils.sl(files_err) }, {})
      return
    end
    load_viewed()
    if #state.files == 0 then
      utils.write_buf(state.panel_buf, ns_panel, { "", "  (no changed files)" }, {})
      show_message("this pull request has no file changes")
      return
    end
    close_picker()
    refilter(keep)
    open_picker()
    fetch.fetch_review_comments(item.number, item.repo, function(list)
      if not is_open() then return end
      state.comments = list
      render_panel()
      local f = state.visible[state.index]
      if f then draw_comments(f) end
    end)
  end

  fetch.fetch_meta(item.number, item.repo, function(err, meta)
    state.meta = (not err) and meta or { head_sha = "", base_sha = "" }
    ready()
  end)
  fetch.fetch_files(item.number, item.repo, function(err, files)
    files_err   = err
    state.files = files or {}
    ready()
  end)
end

function M.setup()
  highlights.setup()
end

return M
