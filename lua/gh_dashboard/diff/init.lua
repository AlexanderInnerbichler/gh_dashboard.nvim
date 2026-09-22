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
    review_key     = "",
    meta           = nil,
    files          = {},
    visible        = {},
    index          = 0,
    layout         = "side_by_side",
    hide_generated = true,
    comments       = {},
    line_of_index  = {},
    row_map        = {},
    hunks          = {},
    ranges         = {},
    line_map       = {},
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
    if not p:match("^context:") then
      table.insert(parts, p)
    end
  end
  table.insert(parts, "context:" .. opts().context)
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
  return string.format(" PR #%d   %s   %d files ",
    state.item.number, state.item.repo, #state.files)
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
  for _, c in ipairs(review.all(state.review_key)) do
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
    pending          = review.all(state.review_key),
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
  "q files  <Tab> next file  c comment on selection  A submit review  ? help",
  "q files  <Tab> next  c comment  A submit  ? help",
  "c comment  A submit  ? help",
  "? help",
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
    footer     = " <CR> open   q close ",
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
  for _, c in ipairs(review.for_path(state.review_key, path)) do
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
    view.overlay_comments(state.head_buf, ns_head, remapped, width)
  else
    view.overlay_comments(state.head_buf, ns_head, entries_for(f.path, "RIGHT"), width)
    if state.base_buf then
      view.overlay_comments(state.base_buf, ns_base, entries_for(f.path, "LEFT"), width)
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
  local lines, hl_specs, line_map = patch.render_unified(state.hunks)
  state.line_map = line_map
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

-- ── file list ──────────────────────────────────────────────────────────────

local function arrange_files(keep_path)
  keep_path = keep_path or (state.visible[state.index] and state.visible[state.index].path)
  state.visible = panel.arrange(state.files, {
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
    show_message("every changed file is hidden as generated")
  else
    open_file(state.index)
  end
end

-- ── actions ────────────────────────────────────────────────────────────────

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
      review.add(state.review_key,
                 vim.tbl_extend("force", target, { body = body, login = "you" }))
      local f = state.visible[state.index]
      if f then draw_comments(f) end
      render_panel()
      vim.notify(string.format("Queued (%d pending) — press A to submit",
                                review.count(state.review_key)),
                 vim.log.levels.INFO)
    end)
  end)
end

--- The key you submit with picks the review event, so there is one float
--- instead of a picker feeding a second one. Opening the summary prompt from
--- inside vim.ui.select's callback let that picker's own teardown close it
--- again, which dropped whole reviews without a word.
local SUBMITS = {
  ["<C-s>"] = "COMMENT",
  ["<C-a>"] = "APPROVE",
  ["<C-r>"] = "REQUEST_CHANGES",
  ["<C-d>"] = "DISCARD",
}

local function refresh_comments()
  fetch.fetch_review_comments(state.item.number, state.item.repo, function(list)
    if not is_open() then return end
    state.comments = list
    render_panel()
    local f = state.visible[state.index]
    if f then draw_comments(f) end
  end)
end

local function queued_label(n)
  return string.format("%d comment%s", n, n == 1 and "" or "s")
end

--- Send the queue as one review. A failed submit leaves the queue alone, so a
--- rejected review can be retried rather than retyped.
local function post_review(event, body, pending)
  review.submit(state.review_key, state.item.number, state.item.repo,
                state.meta.head_sha, event, body, function(err)
    if err then
      vim.notify("Review failed: " .. err .. " — " .. queued_label(pending) .. " still queued",
                 vim.log.levels.ERROR)
      return
    end
    vim.notify("Review submitted", vim.log.levels.INFO)
    refresh_comments()
  end)
end

local function discard_review(pending)
  review.clear(state.review_key)
  render_panel()
  local f = state.visible[state.index]
  if f then draw_comments(f) end
  vim.notify("Discarded " .. queued_label(pending), vim.log.levels.INFO)
end

--- One float, and the key you submit with picks the event. Feeding the summary
--- prompt from a vim.ui.select meant it opened inside that picker's callback,
--- and the picker's own teardown left it in normal mode -- so the summary you
--- typed ran as commands and the review went nowhere, silently.
local function submit_review()
  local pending = review.count(state.review_key)
  local queued  = queued_label(pending)

  utils.prompt({
    title   = pending == 0 and "Review — summary only" or ("Review — " .. queued .. " queued"),
    lines   = 12,
    submits = SUBMITS,
    footer  = " <C-s> comment   <C-a> approve   <C-r> request changes"
           .. "   <C-d> discard   <Esc><Esc> cancel ",
  }, function(body, event)
    if event == "DISCARD" then
      discard_review(pending)
    elseif body == "" and pending == 0 then
      vim.notify("Nothing to submit", vim.log.levels.WARN)
    elseif body == "" and event ~= "APPROVE" then
      -- GitHub rejects a comment or request-changes review carrying no summary,
      -- and that rejection takes the queued comments down with it.
      vim.notify("GitHub needs a summary for this review — nothing sent, "
                 .. queued .. " still queued", vim.log.levels.WARN)
    else
      post_review(event, body, pending)
    end
  end, function()
    if pending > 0 then
      vim.notify("Review not sent — " .. queued .. " still queued", vim.log.levels.WARN)
    end
  end)
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

local function focus(win)
  if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
end

--- Six keys. Everything else the viewer bound was a command competing for
--- attention with the one that matters: select a snippet, comment on it.
local function register_keymaps()
  map_all("q",       function() open_picker() end)
  map_all("<Esc>",   function() open_picker() end)
  map_all("<Tab>",   function() goto_file(1) end)
  map_all("<S-Tab>", function() goto_file(-1) end)
  map_all("c",       function() add_comment("normal") end)
  map_all("c",       function() add_comment("visual") end, "x")
  map_all("A",       submit_review)

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

  if was_open then M.close() end

  reset_state()
  state.item           = item
  state.layout         = layout
  state.hide_generated = opts().hide_generated
  state.review_key     = review.key(item.repo, item.number)

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
    if #state.files == 0 then
      utils.write_buf(state.panel_buf, ns_panel, { "", "  (no changed files)" }, {})
      show_message("this pull request has no file changes")
      return
    end
    close_picker()
    arrange_files(keep)
    open_picker()
    refresh_comments()
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
