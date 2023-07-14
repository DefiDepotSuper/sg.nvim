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
  local lib = require "sg.lib"
  if lib then
    vim.health.ok "Found `libsg_nvim`"
    return true
  else
    vim.health.error "Unable to find `libsg_nvim`"
    return false
  end
end

local report_env = function()
  local env = require "sg.env"

  local ok = true

  if not env.token() or env.token() == "" then
    ok = false
    vim.health.error "$SRC_ACCESS_TOKEN is not set in the environment."
  end

  if not env.endpoint() or env.endpoint() == "" then
    ok = false
    vim.health.error "$SRC_ENDPOINT is not set in the environment."
  end

  if ok then
    vim.health.ok "Environment variables set"
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
      vim.health.ok(string.format("config.node_executable (%s) is executable", config.node_executable))
    end
  end

  if not config.cody_agent then
    vim.health.error "Unable to find cody_agent `cody-agent.js` file"
  else
    vim.health.ok(string.format("Found Cody agent: %s", config.cody_agent))
  end

  return true
end

M.check = function()
  vim.health.start "sg.nvim report"

  local ok = true

  ok = report_nvim() and ok
  ok = report_lib() and ok
  ok = report_env() and ok
  ok = report_agent() and ok

  if ok then
    vim.health.ok "sg.nvim is ready to run"
  else
    vim.health.error "sg.nvim has issues that need to be resolved"
  end
end

return M
