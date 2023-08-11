local M = {}

M.NO_AUTH = function()
  vim.notify_once "[sg-cody] Unable to find valid authentication strategy. See `:help sg.auth` and then restart nvim"

  return nil
end

M.NO_BUILD = function()
  vim.notify_once "[sg-cody] Unable to find cody binaries. You may not have run `nvim -l build/init.lua` and then restart nvim"

  return nil
end

M.INVALID_AUTH = function()
  vim.notify_once "[sg-cody] Invalid authentication. See `:help sg.auth`"
end

M.CODY_DISABLED = function()
  vim.notify_once "[sg-cody] Cody is disabled for your current instance. Please talk to site-admins or change authentication"
end

return M
