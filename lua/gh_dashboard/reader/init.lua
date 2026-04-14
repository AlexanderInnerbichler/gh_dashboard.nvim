local M        = {}
local highlights = require("gh_dashboard.highlights")
local fetch      = require("gh_dashboard.reader.fetch")
local render     = require("gh_dashboard.reader.render")
local actions    = require("gh_dashboard.reader.actions")

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  buf           = nil,
  win           = nil,
  item          = nil,
  data          = nil,
  input_buf     = nil,
  input_win     = nil,
  diff_item     = nil,
  diff_line_map = {},
  diff_head_sha = nil,
}

-- ── namespace ──────────────────────────────────────────────────────────────

local ns = vim.api.nvim_create_namespace("GhReader")

-- ── buffer I/O ────────────────────────────────────────────────────────────

local function write_buf(lines, hl_specs)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    local col_e = spec.col_e == -1 and -1 or spec.col_e
    vim.api.nvim_buf_add_highlight(state.buf, ns, spec.hl, spec.line, spec.col_s, col_e)
  end
end

-- ── window management ──────────────────────────────────────────────────────

local function close_popup()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  end
end

local function close_input()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, false)
    state.input_win = nil
    state.input_buf = nil
    vim.cmd("stopinsert")
  end
end

local function sl(s) return s:gsub("[\n\r]", " ") end

local function register_keymaps()
  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end
  local function back()
    close_popup()
    require("gh_dashboard").focus_win()
  end
  bmap("q",     back)
  bmap("<Esc>", back)
  bmap("r", function()
    if state.item then M.open(state.item) end
  end)
  bmap("c", function()
    if not state.item then return end
    local item = state.item
    M.open_input("Write comment  |  <C-s> submit  ·  <Esc><Esc> cancel", function(body)
      if body == "" then return end
      actions.post_comment(item, body, function(err)
        if err then
          vim.notify("Comment failed: " .. err, vim.log.levels.ERROR)
        else
          vim.notify("Comment posted", vim.log.levels.INFO)
          M.open(item)
        end
      end)
    end)
  end)
  bmap("a", function()
    if not state.item or state.item.kind ~= "pr" then return end
    local item = state.item
    vim.ui.select(
      { "Approve", "Request Changes", "Comment Only", "Cancel" },
      { prompt = "Review type:" },
      function(choice)
        if not choice or choice == "Cancel" then return end
        local kind_map = {
          ["Approve"]          = "approve",
          ["Request Changes"]  = "request_changes",
          ["Comment Only"]     = "comment",
        }
        local kind = kind_map[choice]
        M.open_input(choice .. "  |  <C-s> submit  ·  <Esc><Esc> cancel", function(body)
          actions.submit_review(item, kind, body, function(err)
            if err then
              vim.notify("Review failed: " .. err, vim.log.levels.ERROR)
            else
              vim.notify("Review submitted", vim.log.levels.INFO)
              M.open(item)
            end
          end)
        end)
      end
    )
  end)
  bmap("m", function()
    if not state.item or state.item.kind ~= "pr" then return end
    if not state.data then return end
    local item = state.item
    if state.data.mergeable ~= "MERGEABLE" then
      vim.notify("Cannot merge: " .. tostring(state.data.mergeable), vim.log.levels.WARN)
      return
    end
    vim.ui.select(
      { "Merge commit", "Squash and merge", "Rebase and merge", "Cancel" },
      { prompt = "Merge method:" },
      function(choice)
        if not choice or choice == "Cancel" then return end
        local method_map = {
          ["Merge commit"]      = "merge",
          ["Squash and merge"]  = "squash",
          ["Rebase and merge"]  = "rebase",
        }
        local method = method_map[choice]
        local base   = tostring(state.data.base_ref or "")
        vim.ui.input(
          { prompt = "Merge #" .. item.number .. " into " .. base .. "? (yes/no): " },
          function(ans)
            if ans ~= "yes" then return end
            actions.merge_pr(item, method, function(err)
              if err then
                vim.notify("Merge failed: " .. err, vim.log.levels.ERROR)
              else
                vim.notify("PR #" .. item.number .. " merged", vim.log.levels.INFO)
                vim.uv.fs_unlink(vim.fn.expand("~/.cache/nvim/gh-dashboard.json"), function() end)
                M.open(item)
              end
            end)
          end
        )
      end
    )
  end)
  bmap("d", function()
    if state.item and state.item.kind == "pr" then M.open_diff(state.item) end
  end)
  bmap("x", function()
    if not state.item or state.item.kind ~= "issue" then return end
    local item = state.item
    vim.ui.input(
      { prompt = "Close issue #" .. item.number .. "? (yes/no): " },
      function(ans)
        if ans ~= "yes" then return end
        actions.close_issue(item, function(err)
          if err then
            vim.notify("Close failed: " .. err, vim.log.levels.ERROR)
          else
            vim.notify("Issue #" .. item.number .. " closed", vim.log.levels.INFO)
            vim.uv.fs_unlink(vim.fn.expand("~/.cache/nvim/gh-dashboard.json"), function() end)
            M.open(item)
          end
        end)
      end
    )
  end)
end

local function open_popup(title, footer)
  footer = footer or ""
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype    = "nofile"
    vim.bo[state.buf].bufhidden  = "wipe"
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].filetype   = "text"
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      title      = " " .. title .. " ",
      title_pos  = "center",
      footer     = footer ~= "" and (" " .. footer .. " ") or nil,
      footer_pos = "center",
    })
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
    title      = " " .. title .. " ",
    title_pos  = "center",
    footer     = footer ~= "" and (" " .. footer .. " ") or nil,
    footer_pos = "center",
  })
  vim.wo[state.win].number         = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn     = "no"
  vim.wo[state.win].wrap           = true
  vim.wo[state.win].linebreak      = true
  vim.wo[state.win].cursorline     = false
  register_keymaps()
end

-- ── input buffer ───────────────────────────────────────────────────────────

function M.open_input(hint, on_submit)
  close_input()

  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].buftype   = "nofile"
  vim.bo[state.input_buf].bufhidden = "wipe"
  vim.bo[state.input_buf].filetype  = "markdown"

  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "", "" })

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * 0.60)
  local height = 12
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)

  state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " " .. hint .. " ",
    title_pos  = "center",
    footer     = " <C-s> submit  ·  <Esc><Esc> cancel ",
    footer_pos = "center",
  })
  vim.wo[state.input_win].number         = false
  vim.wo[state.input_win].relativenumber = false
  vim.wo[state.input_win].signcolumn     = "no"
  vim.wo[state.input_win].wrap           = true
  vim.wo[state.input_win].linebreak      = true

  vim.api.nvim_win_set_cursor(state.input_win, { 1, 0 })
  vim.cmd("startinsert")

  local function do_submit()
    local all_lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
    local body = table.concat(all_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    close_input()
    on_submit(body)
  end

  local function imap(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = state.input_buf, nowait = true, silent = true })
  end
  imap("n", "<C-s>",     do_submit)
  imap("i", "<C-s>",     do_submit)
  imap("n", "<Esc><Esc>", close_input)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer   = state.input_buf,
    once     = true,
    callback = function()
      state.input_buf = nil
      state.input_win = nil
    end,
  })
end

-- ── public API ─────────────────────────────────────────────────────────────

function M.open(item)
  state.item = item
  state.data = nil
  local label = item.number and ("#" .. tostring(item.number)) or (item.full_name or item.repo or "…")
  open_popup(label .. " — loading…", "q back")

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
    "  GitHub Dashboard  ›  " .. label,
    "",
    "  ⠋ loading " .. label .. "…",
  })
  vim.bo[state.buf].modifiable = false

  if item.kind == "issue" then
    fetch.fetch_issue(item, function(err, data)
      if err then
        vim.bo[state.buf].modifiable = true
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "", "  ✗ " .. sl(err) })
        vim.bo[state.buf].modifiable = false
        return
      end
      state.data = data
      local lines, hl_specs, title, footer = render.render_issue(data)
      open_popup(title, footer)
      write_buf(lines, hl_specs)
    end)
  elseif item.kind == "pr" then
    local pr_data, rc_data
    local pending = 2
    local function on_both()
      pending = pending - 1
      if pending > 0 then return end
      state.data = pr_data
      local lines, hl_specs, title, footer = render.render_pr(pr_data, rc_data or {})
      open_popup(title, footer)
      write_buf(lines, hl_specs)
    end
    fetch.fetch_pr(item, function(err, data)
      if err then
        vim.bo[state.buf].modifiable = true
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "", "  ✗ " .. sl(err) })
        vim.bo[state.buf].modifiable = false
        return
      end
      pr_data = data
      on_both()
    end)
    fetch.fetch_review_comments(item.number, item.repo, function(data)
      rc_data = data
      on_both()
    end)
  elseif item.kind == "repo" then
    fetch.fetch_readme(item, function(err, body)
      if err then
        vim.bo[state.buf].modifiable = true
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "", "  ✗ " .. sl(err) })
        vim.bo[state.buf].modifiable = false
        return
      end
      local lines, hl_specs, title, footer = render.render_readme({ full_name = item.full_name, body = body })
      open_popup(title, footer)
      write_buf(lines, hl_specs)
    end)
  end
end

M.open_diff = function(item)
  open_popup(string.format(" PR #%d diff ", item.number), " c comment · q close ")
  vim.wo[state.win].wrap = false

  state.diff_item     = item
  state.diff_line_map = {}
  state.diff_head_sha = nil

  write_buf({ "", "  Loading diff…" }, {})

  vim.keymap.set("v", "c", function()
    local end_ln = vim.fn.getpos("'>")[2] - 1
    local info   = state.diff_line_map[end_ln]
    if not info then
      vim.cmd("normal! \27")
      vim.notify("Cannot comment on this line", vim.log.levels.INFO)
      return
    end
    if not state.diff_head_sha or state.diff_head_sha == "" then
      vim.cmd("normal! \27")
      vim.notify("Still loading, please try again", vim.log.levels.INFO)
      return
    end
    vim.cmd("normal! \27")
    M.open_input("Review comment  |  <C-s> submit  ·  <Esc><Esc> cancel", function(body)
      if body == "" then
        vim.notify("Comment cannot be empty", vim.log.levels.WARN)
        return
      end
      fetch.post_review_comment(
        state.diff_item.number, state.diff_item.repo,
        state.diff_head_sha, info.path, info.line, info.side,
        body, function(err)
          if err then
            vim.notify("Failed: " .. err:gsub("[\n\r]", " "), vim.log.levels.ERROR)
          else
            vim.notify("Review comment posted", vim.log.levels.INFO)
          end
        end
      )
    end)
  end, { buffer = state.buf, nowait = true, silent = true })

  local pending = 2
  local diff_text, diff_err, head_sha

  local function on_both()
    pending = pending - 1
    if pending > 0 then return end
    state.diff_head_sha = head_sha or ""
    local lines, hl_specs = {}, {}
    table.insert(lines, "")
    render.render_diff_content(lines, hl_specs, item.number, item.repo,
                               diff_text or "", diff_err, state.diff_line_map)
    table.insert(lines, "")
    write_buf(lines, hl_specs)
  end

  fetch.fetch_diff(item.number, item.repo, function(err, text)
    diff_err, diff_text = err, text
    on_both()
  end)
  fetch.fetch_head_sha(item.number, item.repo, function(_, sha)
    head_sha = sha
    on_both()
  end)
end

-- expose action shortcuts so callers don't need to require actions directly
M.post_comment  = actions.post_comment
M.submit_review = actions.submit_review
M.merge_pr      = actions.merge_pr
M.close_issue   = actions.close_issue

function M.setup()
  highlights.setup()
end

return M
