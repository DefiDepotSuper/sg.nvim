local _ = require "sg.components.shared"
local keymaps = require "sg.keymaps"

local CodyHistory = require "sg.components.cody_history"

local Message = require "sg.cody.message"
local Speaker = require "sg.cody.speaker"
local State = require "sg.cody.state"

local context = require "sg.cody.context"
local void = require("plenary.async").void
local util = require "sg.utils"

---@class CodyFloatLayoutOptions
---@field name string?
---@field history CodyHistoryOptions
---@field width number?
---@field state CodyState?
---@field bufnr number?
---@field start_line number?
---@field end_line number?
---@field code_response boolean?

---@class CodyFloatLayout
---@field opts CodyFloatLayoutOptions
---@field state CodyState
---@field history CodyHistory
---@field active CodyFloatLayout?
local CodyFloatLayout = {}
CodyFloatLayout.__index = CodyFloatLayout

--- Create a new CodyFloatLayout
---@param opts CodyFloatLayoutOptions
---@return CodyFloatLayout
CodyFloatLayout.init = function(opts)
  opts.history = opts.history or {}

  local width = opts.width or 0.25
  opts.history.width = width

  opts.history.height = 30

  local cursor = vim.api.nvim_win_get_cursor(0)

  local line_number_width = 0
  if vim.wo.number or vim.wo.relativenumber then
    line_number_width = vim.wo.numberwidth + 1
  end
  opts.history.row = cursor[1]
  opts.history.col = cursor[2] + line_number_width
  if opts.code_response then
    opts.history.filetype = vim.bo[opts.bufnr].filetype
  end

  ---@type CodyFloatLayout
  local self = {
    opts = opts,
    state = opts.state or State.init {
      name = opts.name,
    },
  }

  return setmetatable(self, CodyFloatLayout)
end

function CodyFloatLayout:render()
  self.state:render(self.history.bufnr, self.history.win)
end

local callback = function(noti)
  local active = CodyFloatLayout.active

  if active then
    active.state:update_message(Message.init(Speaker.cody, vim.split(noti.text, "\n")))
    active:render()
  else
    local layout = CodyFloatLayout.init {}
    layout:mount()

    layout.state:update_message(Message.init(Speaker.cody, vim.split(noti.text, "\n")))
    layout:render()
  end
end

local code_callback = function(noti)
  local active = CodyFloatLayout.active
  local lines = {}
  for _, line in ipairs(vim.split(noti.text, "\n")) do
    -- This is to trim the rambling at the end that LLMs tend to do.
    -- TODO: This should be handled in the agent/LSP/whatever doing
    -- the GQL request, so that the response can be cut short
    -- without having to wait for the stream to complete. No sense
    -- waiting for text to complete that you're going to throw
    -- away.
    if line == "```" then
      require("sg.cody.rpc").message_callbacks[noti.data.id] = nil
      break
    end
    table.insert(lines, line)
  end

  if active then
    active.state:update_message(Message.init(Speaker.cody, lines))
    active:render()
  else
    local layout = CodyFloatLayout.init {}
    layout:mount()

    layout.state:update_message(Message.init(Speaker.cody, lines))
    layout:render()
  end
end

function CodyFloatLayout:complete()
  if self.opts.code_response then
    self.state:complete(self.history.bufnr, self.history.win, true, code_callback)
  else
    self.state:complete(self.history.bufnr, self.history.win, false, callback)
  end
end

function CodyFloatLayout:mount()
  if CodyFloatLayout.active then
    CodyFloatLayout.active:unmount()
  end

  self.history = CodyHistory.init(self.opts.history)
  self.history:mount()

  keymaps.map(self.history.bufnr, "n", "<CR>", "[cody] confirm edit", function()
    vim.api.nvim_buf_set_lines(
      self.opts.bufnr,
      self.opts.start_line,
      self.opts.end_line,
      false,
      vim.api.nvim_buf_get_lines(self.history.bufnr, 0, -1, false)
    )
    self.history:hide()
  end)

  keymaps.map(self.history.bufnr, "n", "<ESC>", "[cody] quit float layout", function()
    self.history:hide()
  end)

  CodyFloatLayout.active = self
  vim.api.nvim_set_current_win(self.history.win)
end

function CodyFloatLayout:show()
  self.history:mount()
  vim.api.nvim_set_current_win(self.history.win)
end

function CodyFloatLayout:hide()
  self.history:hide()
end

function CodyFloatLayout:unmount()
  self.history:unmount()

  CodyFloatLayout.active = nil
end

function CodyFloatLayout:run(f)
  void(f)()
end

return CodyFloatLayout