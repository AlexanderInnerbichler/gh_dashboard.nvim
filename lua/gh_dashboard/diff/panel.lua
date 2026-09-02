local M     = {}
local utils = require("gh_dashboard.utils")

local BAR_W = 5
local FULL, EMPTY = "▇", "▁"

local STATUS_CHAR = {
  added    = "A", removed  = "D", modified = "M",
  renamed  = "R", copied   = "C", changed  = "M", unchanged = " ",
}

local STATUS_HL = {
  A = "GhDiffStatAdd", D = "GhDiffStatDel", M = "GhDiffStatMod",
  R = "GhDiffStatRen", C = "GhDiffStatRen", [" "] = "GhReaderMeta",
}

-- ── filtering & ordering ───────────────────────────────────────────────────

local function matches_glob(path, glob)
  local pat  = vim.fn.glob2regpat(glob)
  local base = path:match("[^/]+$") or path
  return vim.fn.match(path, pat) >= 0 or vim.fn.match(base, pat) >= 0
end

function M.is_generated(path, globs)
  for _, g in ipairs(globs or {}) do
    if matches_glob(path, g) then return true end
  end
  return false
end

local SORTERS = {
  path   = function(a, b) return a.path < b.path end,
  size   = function(a, b)
    local ca, cb = a.add + a.del, b.add + b.del
    if ca ~= cb then return ca > cb end
    return a.path < b.path
  end,
  status = function(a, b)
    if a.status ~= b.status then return a.status < b.status end
    return a.path < b.path
  end,
}

M.SORT_ORDER = { "path", "size", "status" }

--- Apply the current filter / generated-file toggle / sort to the file list.
function M.arrange(files, opts)
  local out = {}
  local needle = (opts.filter or ""):lower()
  for _, f in ipairs(files) do
    local keep = true
    if needle ~= "" and not f.path:lower():find(needle, 1, true) then keep = false end
    if keep and opts.hide_generated and M.is_generated(f.path, opts.generated_globs) then
      keep = false
    end
    if keep then table.insert(out, f) end
  end
  table.sort(out, SORTERS[opts.sort] or SORTERS.path)
  return out
end

-- ── rendering helpers ──────────────────────────────────────────────────────

--- Trim a path from the left on a directory boundary, e.g. "…/ex_cmds/cd_spec.lua".
local function fit_path(path, width)
  if #path <= width then return path end
  local segments = vim.split(path, "/", { plain = true })
  local out = segments[#segments]
  for i = #segments - 1, 1, -1 do
    local candidate = segments[i] .. "/" .. out
    if #candidate + 2 > width then break end
    out = candidate
  end
  if #out + 2 > width then out = out:sub(#out - width + 3) end
  return "…/" .. out
end

local function bar(add, del, max_change)
  local change = add + del
  if change == 0 or max_change == 0 then return string.rep(EMPTY, BAR_W), 0, 0 end
  local filled = math.max(1, math.ceil(BAR_W * change / max_change))
  local n_add  = math.floor(filled * add / change + 0.5)
  if add > 0 and n_add == 0 then n_add = 1 end
  if del > 0 and n_add == filled then n_add = filled - 1 end
  local n_del = filled - n_add
  return string.rep(FULL, n_add) .. string.rep(FULL, n_del)
       .. string.rep(EMPTY, BAR_W - filled), n_add, n_del
end

-- ── panel buffer ───────────────────────────────────────────────────────────

--- Build the file panel.
--- Returns lines, hl_specs, row_map (0-based buf line -> index into visible).
function M.render(ctx)
  local lines, hl_specs, row_map = {}, {}, {}
  local width = ctx.width

  local function add(text, hl)
    table.insert(lines, text)
    if hl then
      table.insert(hl_specs, { hl = hl, line = #lines - 1, col_s = 0, col_e = -1 })
    end
    return #lines - 1
  end

  add("")
  add("  PR #" .. ctx.number, "GhReaderTitle")
  add("  " .. utils.trunc(ctx.repo, width - 4), "GhReaderBreadcrumb")

  local total_add, total_del, max_change = 0, 0, 0
  for _, f in ipairs(ctx.files) do
    total_add, total_del = total_add + f.add, total_del + f.del
    max_change = math.max(max_change, f.add + f.del)
  end

  do
    local stat = string.format("  %d files  +%d  −%d", #ctx.files, total_add, total_del)
    local ln   = add(stat)
    local plus = stat:find("%+")
    local minus = stat:find("−")
    table.insert(hl_specs, { hl = "GhReaderMeta",  line = ln, col_s = 0,        col_e = plus - 1 })
    table.insert(hl_specs, { hl = "GhDiffAdd",     line = ln, col_s = plus - 1, col_e = minus - 1 })
    table.insert(hl_specs, { hl = "GhDiffDel",     line = ln, col_s = minus - 1, col_e = -1 })
  end

  local viewed_n = 0
  for _, f in ipairs(ctx.files) do
    if ctx.viewed[f.path] then viewed_n = viewed_n + 1 end
  end
  add(string.format("  %d/%d viewed", viewed_n, #ctx.files), "GhDiffViewed")

  if #ctx.pending > 0 then
    add(string.format("  %d pending comment%s", #ctx.pending, #ctx.pending == 1 and "" or "s"),
        "GhDiffCommentPending")
  end

  local notes = {}
  if ctx.filter ~= ""     then table.insert(notes, "/" .. ctx.filter) end
  if ctx.hide_generated   then table.insert(notes, "no-gen")          end
  if ctx.skip_whitespace  then table.insert(notes, "no-ws")           end
  table.insert(notes, ctx.sort)
  add("  " .. table.concat(notes, " · "), "GhReaderMeta")

  add(string.rep("─", width), "GhReaderSep")

  if #ctx.visible == 0 then
    add("")
    add("  (no files match)", "GhReaderEmpty")
    return lines, hl_specs, row_map
  end

  for i, f in ipairs(ctx.visible) do
    local mark   = ctx.viewed[f.path] and "✓" or " "
    local status = STATUS_CHAR[f.status] or "?"
    local avail  = width - 8
    local shown  = fit_path(f.path, avail)

    local prefix = "  " .. mark .. " " .. status .. " "
    local ln = add(prefix .. shown)
    row_map[ln] = i

    table.insert(hl_specs, { hl = "GhDiffViewed", line = ln, col_s = 2, col_e = 3 })
    table.insert(hl_specs, {
      hl = STATUS_HL[status] or "GhReaderMeta", line = ln, col_s = 4, col_e = 5,
    })

    local slash = shown:match(".*()/")
    if slash then
      table.insert(hl_specs, { hl = "GhDiffPanelDir",  line = ln, col_s = #prefix, col_e = #prefix + slash })
      table.insert(hl_specs, { hl = "GhDiffPanelPath", line = ln, col_s = #prefix + slash, col_e = -1 })
    else
      table.insert(hl_specs, { hl = "GhDiffPanelPath", line = ln, col_s = #prefix, col_e = -1 })
    end

    local graph, n_add = bar(f.add, f.del, max_change)
    local counts = string.format("      +%-5d −%-5d ", f.add, f.del)
    local ln2 = add(counts .. graph)
    row_map[ln2] = i

    local plus  = counts:find("%+")
    local minus = counts:find("−")
    table.insert(hl_specs, { hl = "GhDiffAdd", line = ln2, col_s = plus - 1,  col_e = minus - 1 })
    table.insert(hl_specs, { hl = "GhDiffDel", line = ln2, col_s = minus - 1, col_e = #counts })
    local bar_s = #counts
    table.insert(hl_specs, { hl = "GhDiffBarAdd", line = ln2, col_s = bar_s, col_e = bar_s + n_add * #FULL })
    table.insert(hl_specs, { hl = "GhDiffBarDel", line = ln2, col_s = bar_s + n_add * #FULL, col_e = -1 })

    if ctx.comments_by_path[f.path] then
      local n   = #ctx.comments_by_path[f.path]
      local tag = string.format(" %d ", n)
      lines[ln2 + 1] = lines[ln2 + 1] .. "  " .. tag
      table.insert(hl_specs, {
        hl = "GhDiffCommentAuthor", line = ln2,
        col_s = #(counts .. graph) + 2, col_e = -1,
      })
    end
  end

  -- Comments GitHub can no longer anchor (the line they targeted has changed).
  -- Listing them here beats dropping them or pinning them to the wrong line.
  if #ctx.outdated > 0 then
    add("")
    add(string.rep("─", width), "GhReaderSep")
    add("  outdated comments", "GhReaderSection")
    for _, c in ipairs(ctx.outdated) do
      add("  @" .. (c.login or "?") .. "  " .. utils.trunc(c.path:match("[^/]+$") or c.path, width - 8),
          "GhDiffCommentAuthor")
      for _, l in ipairs(vim.split(utils.trunc(c.body, 160), "\n", { plain = true })) do
        add("    " .. utils.trunc(l, width - 6), "GhDiffCommentBody")
      end
    end
  end

  return lines, hl_specs, row_map
end

return M
