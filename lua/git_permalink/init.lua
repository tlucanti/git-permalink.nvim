-- =============================================================================
--  git_permalink/init.lua
--  Build a per‑line permalink for GitHub / GitLab / Bitbucket (including private
--  instances and nested sub-modules) and copy it to the system clipboard.
-- =============================================================================
local M = {}

--------------------------------------------------------------------
-- DEFAULT configuration -------------------------------------------------
--------------------------------------------------------------------
local default_cfg = {
  -- Which remote to query – usually "origin"
  remote_name = "origin",
  -- Mapping key (you can change it if you want a different hot‑key)
  lhs = "<C-l>",   -- normal‑mode default
  mode = "n",      -- normal mode (could be "v" for visual, etc.)
  desc = "Copy Git line‑permalink to clipboard",
}

--------------------------------------------------------------------
-- Utility helpers ----------------------------------------------------
--------------------------------------------------------------------
-- Execute a shell command.  If *cwd* is supplied, the command is run
-- inside that directory using `git -C <cwd> …` (which works for any
-- git sub‑command).  Returns the first line of output, or nil on error.
local function syscmd(cmd, cwd)
  local full_cmd = cmd
  if cwd then
    -- All callers that pass a cwd are running a git command, so we can safely
    -- prepend the `-C` flag.  For non‑git commands the caller should omit cwd.
    full_cmd = string.format('git -C %q %s', cwd, cmd:gsub("^git%s+", "")) -- strip leading "git"
  end
  local out = vim.fn.systemlist(full_cmd)
  if vim.v.shell_error ~= 0 or #out == 0 then return nil end
  return out[1]:gsub("%s+$", "")      -- trim trailing newline / spaces
end

-- Very small URL‑encoder – enough for file paths
local function url_encode(str)
  return (str:gsub("[ %?#%%]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- Convert `"git@host:group/repo.git"` or `"ssh://git@host/group/repo.git"` to
-- an HTTPS URL (e.g. `https://host/group/repo`).  Strips a trailing `.git`.
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

-- Return "github", "gitlab" or "bitbucket" if the URL matches (including
-- self‑hosted / enterprise instances).  The check is performed against the
-- hostname part of the URL, allowing patterns such as "example.gitlab.com"
-- or "gitlab.my‑company.io".
local function detect_host(url, cfg)
  local host = url:match("^https?://([^/]+)")
  if not host then return nil end
  host = host:lower()
  local service_patterns = {
    github    = "github",
    gitlab    = "gitlab",
    bitbucket = "bitbucket",
  }
  for service, pat in pairs(service_patterns) do
    if host:find(pat, 1, true) then   -- plain substring search (case‑insensitive)
      return service
    end
  end
  return nil   -- unsupported host
end

--------------------------------------------------------------------
-- Core: build the permalink and copy it to the clipboard -------------
--------------------------------------------------------------------
function M.copy_permalink()
  local cfg = M._cfg or default_cfg   -- configuration is stored on the module

  ----------------------------------------------------------------
  -- 0️⃣  Are we inside a Git repo (or a sub‑module)? -------------
  ----------------------------------------------------------------
  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then
    vim.api.nvim_echo({{"⛔ Buffer has no name (unsaved?)", "ErrorMsg"}}, false, {})
    return
  end
  local buf_dir = vim.fn.fnamemodify(buf_path, ":h")   -- directory of the buffer

  local git_root = syscmd('rev-parse --show-toplevel', buf_dir)
  if not git_root then
    vim.api.nvim_echo({{"⛔ Not inside a Git repository (or sub‑module not initialized)", "ErrorMsg"}}, false, {})
    return
  end

  ----------------------------------------------------------------
  -- 1️⃣  Remote URL (default: origin, can be overridden in cfg) --
  ----------------------------------------------------------------
  local remote_cmd = string.format('remote get-url %s', cfg.remote_name)
  local remote_url = syscmd(remote_cmd, git_root)
  if not remote_url then
    vim.api.nvim_echo({{("⛔ No remote named '"..cfg.remote_name.."' found in this repo"), "ErrorMsg"}}, false, {})
    return
  end

  ----------------------------------------------------------------
  -- 2️⃣  Normalise the remote URL and detect the hosting service --
  ----------------------------------------------------------------
  remote_url = normalize_remote_url(remote_url)
  local host = detect_host(remote_url, cfg)
  if not host then
    vim.api.nvim_echo({{"⛔ Remote host not supported (GitHub, GitLab, Bitbucket)", "ErrorMsg"}}, false, {})
    return
  end

  ----------------------------------------------------------------
  -- 3️⃣  Current branch (fallback to commit SHA if HEAD is detached)
  ----------------------------------------------------------------
  local branch = syscmd('rev-parse --abbrev-ref HEAD', git_root)
  if not branch or branch == "HEAD" then
    branch = syscmd('rev-parse HEAD', git_root)   -- commit SHA
  end

  ----------------------------------------------------------------
  -- 4️⃣  Relative file path inside the (sub‑module) repository ----
  ----------------------------------------------------------------
  -- Path relative to the git root (not to the CWD).  `:h` makes the operation
  -- work even when the buffer is outside the cwd (common when editing a sub‑module).
  local ls_cmd = string.format('ls-files --full-name %s', buf_path)
  local rel_path = syscmd(ls_cmd, buf_dir)

  ----------------------------------------------------------------
  -- 5️⃣  Current line number --------------------------------------
  ----------------------------------------------------------------
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]

  ----------------------------------------------------------------
  -- 6️⃣  Assemble the final permalink (host‑specific template) ----
  ----------------------------------------------------------------
  local url
  if host == "github" then
    -- https://github.com/<user>/<repo>/blob/<branch>/<path>#L<line>
    url = string.format("%s/blob/%s/%s#L%d", remote_url, branch, rel_path, line_nr)
  elseif host == "gitlab" then
    -- https://gitlab.com/<user>/<repo>/-/blob/<branch>/<path>#L<line>
    url = string.format("%s/-/blob/%s/%s#L%d", remote_url, branch, rel_path, line_nr)
  elseif host == "bitbucket" then
    -- https://bitbucket.org/<user>/<repo>/src/<branch>/<path>#lines-<line>
    url = string.format("%s/src/%s/%s#lines-%d", remote_url, branch, rel_path, line_nr)
  end

  ----------------------------------------------------------------
  -- 7️⃣  Copy to system clipboard and echo the link ---------------
  ----------------------------------------------------------------
  vim.fn.setreg('+', url)                     -- system clipboard
  vim.api.nvim_echo({{("🔗 " .. url), "None"}}, false, {})

  -- expose it as a global variable (useful for other plugins)
  vim.g.git_permalink = url
end

--------------------------------------------------------------------
-- Setup helper -------------------------------------------------------
--------------------------------------------------------------------
--- Call this from your `init.lua` (or any plugin config):
function M.setup(user_cfg)
  user_cfg = user_cfg or {}
  -- Merge user_cfg over the defaults (shallow copy is enough)
  M._cfg = vim.tbl_extend("force", {}, default_cfg, user_cfg)

  -- Register the mapping
  vim.keymap.set(M._cfg.mode,
                 M._cfg.lhs,
                 M.copy_permalink,
                 { noremap = true, silent = true, desc = M._cfg.desc })
end

return M
