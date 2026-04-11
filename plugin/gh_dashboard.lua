if vim.g.gh_dashboard_loaded then return end
vim.g.gh_dashboard_loaded = true
-- keymaps and setup() are registered lazily via require("gh_dashboard").setup()
-- The plugin entry point is intentionally minimal; consumers call setup() themselves.
