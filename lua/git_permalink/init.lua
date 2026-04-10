-- =============================================================================
--  git_permalink/init.lua
--  Build a per‑line permalink for GitHub / GitLab / Bitbucket (including private
--  instances) and copy it to the system clipboard.
-- =============================================================================
local M = {}
--------------------------------------------------------------------
-- DEFAULT configuration -------------------------------------------------
--------------------------------------------------------------------
local default_cfg = {
  remote_name = "origin",
  custom_hosts = {
    gitlab    = { "gitlab.dev.syntacore.com", "gitlab.corp.example.com" },
    bitbucket = { "bitbucket.dev.syntacore.com", "bitbucket.corp.example.com" },
  },
  lhs  = "<C-l>",              -- normal‑mode default
  mode = "n",                  -- normal mode (could be "v", "i", …)
  desc = "Copy Git line‑permalink to clipboard",
}
--------------------------------------------------------------------
-- Utility helpers ----------------------------------------------------
--------------------------------------------------------------------
local function syscmd(cmd)
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 or #out == 0 then return nil end
  return out[1]:gsub("%s+$", "")
end

local function url_encode(str)
  return (str:gsub("[ %?#%%]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function normalize_remote_url(url)
  url = url:gsub("%.git$", "")
  if url:match("^git@") then                 -- git@host:group/repo
    url = url:gsub("^git@(.-):", "https://%1/")
  elseif url:match("^ssh://") then           -- ssh://git@host/group/repo
    url = url:gsub("^ssh://git@(.-)/", "https://%1/")
  elseif not url:match("^https?://") then    -- plain host/group/repo
    url = "https://" .. url
  end
  return url
end

local function detect_host(url, cfg)
  if url:match("github.com") then return "github" end
  if url:match("gitlab.com") then return "gitlab" end
  for _, d in ipairs(cfg.custom_hosts.gitlab or {}) do
    if url:find(d, 1, true) then return "gitlab" end
  end
  if url:match("bitbucket.org") then return "bitbucket" end
  for _, d in ipairs(cfg.custom_hosts.bitbucket or {}) do
    if url:find(d, 1, true) then return "bitbucket" end
  end
  return nil
end

--------------------------------------------------------------------
-- Core: build the permalink and copy it to the clipboard -------------
--------------------------------------------------------------------
function M.copy_permalink()
  local cfg = M._cfg or default_cfg

  ----------------------------------------------------------------
  -- 0️⃣  Are we inside a Git repo?
  ----------------------------------------------------------------
  local git_root = syscmd('git rev-parse --show-toplevel')
  if not git_root then
    vim.api.nvim_echo({{"⛔ Not inside a Git repository", "ErrorMsg"}}, false, {})
    return
  end

  ----------------------------------------------------------------
  -- 1️⃣  Remote URL
  ----------------------------------------------------------------
  local remote_cmd = string.format('git remote get-url %s', cfg.remote_name)
  local remote_url = syscmd(remote_cmd)
  if not remote_url then
    vim.api.nvim_echo({{("⛔ No remote named '"..cfg.remote_name.."' found"), "ErrorMsg"}}, false, {})
    return
  end

  ----------------------------------------------------------------
  -- 2️⃣  Normalise & detect host
  ----------------------------------------------------------------
  remote_url = normalize_remote_url(remote_url)
  local host = detect_host(remote_url, cfg)
  if not host then
    vim.api.nvim_echo({{"⛔ Remote host not supported (GitHub, GitLab, Bitbucket)", "ErrorMsg"}}, false, {})
    return
  end

  ----------------------------------------------------------------
  -- 3️⃣  Current branch (or SHA if detached HEAD)
  ----------------------------------------------------------------
  local branch = syscmd('git rev-parse --abbrev-ref HEAD')
  if not branch or branch == "HEAD" then
    branch = syscmd('git rev-parse HEAD')
  end

  ----------------------------------------------------------------
  -- 4️⃣  Relative file path (URL‑encoded)
  ----------------------------------------------------------------
  local abs_path = vim.api.nvim_buf_get_name(0)
  if abs_path == "" then
    vim.api.nvim_echo({{"⛔ Buffer has no name (unsaved?)", "ErrorMsg"}}, false, {})
    return
  end
  local rel_path = vim.fn.fnamemodify(abs_path, ":." .. git_root .. "/")
  rel_path = rel_path:gsub("^%./", "")
  rel_path = url_encode(rel_path)

  ----------------------------------------------------------------
  -- 5️⃣  Current line
  ----------------------------------------------------------------
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]

  ----------------------------------------------------------------
  -- 6️⃣  Assemble final URL
  ----------------------------------------------------------------
  local url
  if host == "github" then
    url = string.format("%s/blob/%s/%s#L%d", remote_url, branch, rel_path, line_nr)
  elseif host == "gitlab" then
    url = string.format("%s/-/blob/%s/%s#L%d", remote_url, branch, rel_path, line_nr)
  elseif host == "bitbucket" then
    url = string.format("%s/src/%s/%s#lines-%d", remote_url, branch, rel_path, line_nr)
  end

  ----------------------------------------------------------------
  -- 7️⃣  Copy & echo
  ----------------------------------------------------------------
  vim.fn.setreg('+', url)
  vim.api.nvim_echo({{("🔗 " .. url), "None"}}, false, {})
  vim.g.git_permalink = url
end

--------------------------------------------------------------------
-- Setup helper -------------------------------------------------------
--------------------------------------------------------------------
function M.setup(user_cfg)
  user_cfg = user_cfg or {}
  M._cfg = vim.tbl_extend("force", {}, default_cfg, user_cfg)

  -- Register the mapping – you can *also* let lazy.nvim do this via `keys`.
  local lhs  = M._cfg.lhs  or "<C-l>"
  local mode = M._cfg.mode or "n"
  local desc = M._cfg.desc or "Copy Git line‑permalink to clipboard"

  vim.keymap.set(mode, lhs, M.copy_permalink,
                 { noremap = true, silent = true, desc = desc })
end

return M
