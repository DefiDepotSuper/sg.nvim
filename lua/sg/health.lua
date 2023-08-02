local M = {}

local report_nvim = function()
  if vim.version.cmp(vim.version(), { 0, 9, 0 }) >= 0 then
    vim.health.ok "Valid nvim version"
    return true
  else
    vim.health.error "Invalid nvim version. Upgrade to at least 0.9.0"
    return false
  end
end

local report_lib = function()
  if 1 ~= vim.fn.executable "cargo" then
    vim.health.error "Unable to find valid cargo executable."
  else
    local result = require("sg.utils").system({ "cargo", "--version" }, { text = true }):wait()
    if result.code ~= 0 then
      vim.health.error "cargo failed to run `cargo --version`"

      for _, msg in ipairs(vim.split(result.stdout, "\n")) do
        vim.health.info(msg)
      end
      for _, msg in ipairs(vim.split(result.stderr, "\n")) do
        vim.health.info(msg)
      end
    else
      vim.health.ok "Found `cargo` is executable"
    end
  end

  local lib = require "sg.lib"
  if lib then
    vim.health.ok(string.format("Found `libsg_nvim`: %s", lib._library_path))
    return true
  else
    vim.health.error "Unable to find `libsg_nvim`"
    return false
  end
end

local report_nvim_agent = function()
  local ok, nvim_agent = pcall(require("sg.config").get_nvim_agent)
  if ok then
    vim.health.ok("Found `sg-nvim-agent`: " .. nvim_agent)
    return true
  else
    vim.health.error("Unable to find `sg-nvim-agent`: " .. nvim_agent)
    return false
  end
end

local report_env = function()
  local auth = require "sg.auth"

  local ok = true

  local creds, strategy = auth.get()

  vim.health.info(string.format("Auth strategy order: %s", vim.inspect(require("sg.config").auth_strategy)))

  if not creds then
    vim.health.error "No valid auth strategy detected. See `:help sg` for more info."
    ok = false
  end

  if ok then
    assert(creds, "must have valid credentials")

    vim.health.ok "Authentication setup correctly"
    vim.health.ok(string.format("  endpoint set to: %s", creds.endpoint))
    vim.health.ok(string.format("  strategy used: %s", strategy))
  end

  local info_ok, info = pcall(require("sg.lib").get_info)
  if not info_ok then
    vim.health.error("Unable to connect to sourcegraph: " .. info)
    ok = false
  else
    vim.health.ok("  Sourcegraph Connection info: " .. vim.inspect(info))
  end

  return ok
end

local report_agent = function()
  local config = require "sg.config"

  if 1 ~= vim.fn.executable(config.node_executable) then
    vim.health.error(string.format("config.node_executable (%s) not executable", config.node_executable))
    return false
  else
    local result = require("sg.utils").system({ config.node_executable, "--version" }, { text = true }):wait()
    if result.code ~= 0 then
      vim.health.error(
        string.format(
          "config.node_executable (%s) failed to run `%s --version`",
          config.node_executable,
          config.node_executable
        )
      )

      for _, msg in ipairs(vim.split(result.stdout, "\n")) do
        vim.health.info(msg)
      end
      for _, msg in ipairs(vim.split(result.stderr, "\n")) do
        vim.health.info(msg)
      end
    else
      vim.health.ok(string.format("Found `%s` (config.node_executable) is executable", config.node_executable))
    end
  end

  if not config.cody_agent then
    vim.health.error "Unable to find cody_agent `cody-agent.js` file"
  else
    vim.health.ok(string.format("Found `cody-agent`: %s", config.cody_agent))
  end

  return true
end

M.check = function()
  vim.health.start "sg.nvim report"

  local ok = true

  ok = report_nvim() and ok
  ok = report_lib() and ok
  ok = report_nvim_agent() and ok
  ok = report_agent() and ok
  ok = report_env() and ok

  if ok then
    vim.health.ok "sg.nvim is ready to run"
  else
    vim.health.error "sg.nvim has issues that need to be resolved"
  end
end

return M
