local M = {}

local registered = false

local function apply()
  -- dashboard
  vim.api.nvim_set_hl(0, "GhTitle",     { fg = "#ffffff", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhUsername",  { fg = "#7fc8f8", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhStats",     { fg = "#616e88",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhStale",     { fg = "#e5c07b",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhSeparator", { fg = "#3b4048",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhSection",   { fg = "#88c0d0", bold = true,   bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhItem",      { fg = "#abb2bf",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhMeta",      { fg = "#4b5263",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhEmpty",     { fg = "#4b5263", italic = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhError",     { fg = "#e06c75",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhSelected",  { bg = "#2c313a",                fg = "#abb2bf" })
  vim.api.nvim_set_hl(0, "GhPush",      { fg = "#7fc8f8",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhPR",        { fg = "#b48ead",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhIssue",     { fg = "#e5c07b",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhPRReview",  { fg = "#61afef",                bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhPRDraft",   { fg = "#616e88", italic = true,  bg = "NONE" })
  -- per-repo issue color palette (cycled by first-seen order)
  vim.api.nvim_set_hl(0, "GhIssueRepo1", { fg = "#7fc8f8", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhIssueRepo2", { fg = "#a3be8c", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhIssueRepo3", { fg = "#e5c07b", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhIssueRepo4", { fg = "#b48ead", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhIssueRepo5", { fg = "#61afef", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhIssueRepo6", { fg = "#e06c75", bg = "NONE" })
  -- heatmap tiers
  vim.api.nvim_set_hl(0, "GhHeat0", { fg = "#1b1f2b", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhHeat1", { fg = "#0d4a3a", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhHeat2", { fg = "#0a7a5c", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhHeat3", { fg = "#10c87e", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhHeat4", { fg = "#00ff99", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhHeat5", { fg = "#00ffFF", bg = "NONE" })
  -- watchlist
  vim.api.nvim_set_hl(0, "GhWatchTitle",     { fg = "#7fc8f8", bold = true   })
  vim.api.nvim_set_hl(0, "GhWatchRepo",      { fg = "#abb2bf"                })
  vim.api.nvim_set_hl(0, "GhWatchNotif",     { fg = "#e5c07b"                })
  vim.api.nvim_set_hl(0, "GhWatchEmpty",     { fg = "#4b5263", italic = true })
  vim.api.nvim_set_hl(0, "GhWatchSep",       { fg = "#3b4048"                })
  vim.api.nvim_set_hl(0, "GhWatchMeta",      { fg = "#4b5263"                })
  vim.api.nvim_set_hl(0, "GhWatchIndicator", { fg = "#e5c07b"                })
  -- user watchlist
  vim.api.nvim_set_hl(0, "GhUserWatchTitle", { fg = "#7fc8f8", bold = true   })
  vim.api.nvim_set_hl(0, "GhUserWatchItem",  { fg = "#abb2bf"                })
  vim.api.nvim_set_hl(0, "GhUserWatchEmpty", { fg = "#4b5263", italic = true })
  vim.api.nvim_set_hl(0, "GhUserWatchMeta",  { fg = "#4b5263"                })
  -- reader
  vim.api.nvim_set_hl(0, "GhReaderTitle",       { fg = "#7fc8f8", bold = true  })
  vim.api.nvim_set_hl(0, "GhReaderMeta",        { fg = "#4b5263"               })
  vim.api.nvim_set_hl(0, "GhReaderStateOpen",   { fg = "#a3be8c", bold = true  })
  vim.api.nvim_set_hl(0, "GhReaderStateClosed", { fg = "#e06c75", bold = true  })
  vim.api.nvim_set_hl(0, "GhReaderStateMerged", { fg = "#b48ead", bold = true  })
  vim.api.nvim_set_hl(0, "GhReaderSep",         { fg = "#3b4048"               })
  vim.api.nvim_set_hl(0, "GhReaderSection",     { fg = "#88c0d0", bold = true  })
  vim.api.nvim_set_hl(0, "GhReaderEmpty",       { fg = "#4b5263", italic = true})
  vim.api.nvim_set_hl(0, "GhReaderError",       { fg = "#e06c75"               })
  vim.api.nvim_set_hl(0, "GhReaderBreadcrumb",  { fg = "#4b5263"               })
  vim.api.nvim_set_hl(0, "GhReaderH2",          { fg = "#88c0d0", bold = true  })
  vim.api.nvim_set_hl(0, "GhReaderH3",          { fg = "#6b7a8d", bold = true  })
  vim.api.nvim_set_hl(0, "GhReaderCode",        { fg = "#4b5263"               })
  vim.api.nvim_set_hl(0, "GhReaderCodeBody",    { fg = "#abb2bf", bg = "#1e1e26"})
  vim.api.nvim_set_hl(0, "GhReaderBullet",      { fg = "#e5c07b"               })
  vim.api.nvim_set_hl(0, "GhReaderQuote",       { fg = "#616e88", italic = true})
  vim.api.nvim_set_hl(0, "GhCiPass",            { fg = "#a3be8c"               })
  vim.api.nvim_set_hl(0, "GhCiFail",            { fg = "#e06c75"               })
  vim.api.nvim_set_hl(0, "GhCiPending",         { fg = "#e5c07b"               })
  vim.api.nvim_set_hl(0, "GhReviewApproved",    { fg = "#a3be8c"               })
  vim.api.nvim_set_hl(0, "GhReviewChanges",     { fg = "#e06c75"               })
  vim.api.nvim_set_hl(0, "GhReviewComment",     { fg = "#616e88"               })
  vim.api.nvim_set_hl(0, "GhDiffAdd",           { fg = "#98c379"               })
  vim.api.nvim_set_hl(0, "GhDiffDel",           { fg = "#e06c75"               })
  vim.api.nvim_set_hl(0, "GhDiffHunk",          { fg = "#61afef"               })
end

function M.setup()
  if registered then return end
  registered = true
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("GhDashboardHL", { clear = true }),
    callback = apply,
  })
end

return M
