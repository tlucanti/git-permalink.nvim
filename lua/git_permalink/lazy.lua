-- lua/git_permalink/lazy.lua
-- This file is *only* executed by lazy.nvim when the plugin is loaded.
-- It forwards the user‑provided `opts` to the real implementation.

local M = {}

--- Called by `lazy.nvim` (see the spec below)
---@param opts table|nil  User configuration table – will be merged with defaults.
function M.init(opts)
  -- Lazily require the actual implementation.
  local perm = require('git_permalink')
  perm.setup(opts or {})
end

return M
