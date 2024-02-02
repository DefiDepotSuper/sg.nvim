local keymaps = require "sg.keymaps"
local shared = require "sg.components.shared"
local util = require "sg.utils"

local Base = require "sg.components.layout.base"

---@class CodyLayoutSplitOpts : CodyBaseLayoutOpts
---@field width number?
---@field state cody.State?
---@field on_submit function?

---@class CodyLayoutSplit : CodyBaseLayout
---@field opts CodyLayoutSplitOpts
---@field super CodyBaseLayout
local CodySplit = setmetatable({}, Base)
CodySplit.__index = CodySplit

---comment
---@param opts CodyLayoutSplitOpts
---@return CodyLayoutSplit
function CodySplit.init(opts)
  opts.prompt = opts.prompt or {}
  opts.history = opts.history or {}

  local width = opts.width or 40
  opts.prompt.width = width
  opts.history.width = width

  opts.prompt.height = opts.prompt.height or 10

  local line_count = vim.o.lines - vim.o.cmdheight
  if vim.o.laststatus ~= 0 then
    line_count = line_count - 1
  end

  opts.history.open = function(history)
    vim.cmd(opts.history.split or "botright vnew")

    history.win = vim.api.nvim_get_current_win()
    history.bufnr = vim.api.nvim_get_current_buf()

    vim.api.nvim_win_set_width(history.win, shared.calculate_width(opts.history.width))

    shared.make_win_minimal(history.win)
    shared.make_buf_minimal(history.bufnr)

    vim.wo[history.win].winbar = "%=Cody History%="
  end

  opts.prompt.open = function(prompt)
    vim.cmd(opts.prompt.split or "below new")
    prompt.win = vim.api.nvim_get_current_win()
    prompt.bufnr = vim.api.nvim_get_current_buf()

    vim.api.nvim_win_set_height(prompt.win, shared.calculate_height(opts.prompt.height))
    shared.make_win_minimal(prompt.win)
    shared.make_buf_minimal(prompt.bufnr)

    vim.wo[prompt.win].winbar = "Cody Prompt%=%#Comment#(`?` for help)"
  end

  local prompt_submit = opts.prompt.on_submit
  opts.prompt.on_submit = function(bufnr, text)
    if prompt_submit then
      prompt_submit(bufnr, text)
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  end

  local object = Base.init(opts) --[[@as CodyLayoutSplit]]

  object.super = Base
  return setmetatable(object, CodySplit) --[[@as CodyLayoutSplit]]
end

function CodySplit:set_keymaps()
  self.super.set_keymaps(self)

  keymaps.map(self.prompt.bufnr, "n", "<CR>", "[cody] submit message", function()
    self.prompt:on_submit()
  end)

  keymaps.map(self.prompt.bufnr, "i", "<C-CR>", "[cody] submit message", function()
    self.prompt:on_submit()
  end)

  keymaps.map(self.prompt.bufnr, { "i", "n" }, "<c-c>", "[cody] quit chat", function()
    self.prompt:on_close()
  end)

  local with_history = function(key, mapped)
    if not mapped then
      mapped = key
    end

    local desc = "[cody] execute '" .. key .. "' in history buffer"
    keymaps.map(self.prompt.bufnr, { "n", "i" }, key, desc, function()
      if vim.api.nvim_win_is_valid(self.history.win) then
        vim.api.nvim_win_call(self.history.win, function()
          util.execute_keystrokes(mapped)
        end)
      end
    end)
  end

  with_history "<c-f>"
  with_history "<c-b>"
  with_history "<c-e>"
  with_history "<c-y>"

  keymaps.map(self.prompt.bufnr, "n", "M", "[cody] show models", function()
    require("sg.cody.rpc.chat").models(self.state.id, function(err, data)
      print("MODELS:", vim.inspect(err), vim.inspect(data))
    end)
  end)

  keymaps.map(self.prompt.bufnr, "n", "?", "[cody] show keymaps", function()
    keymaps.help(self.prompt.bufnr)
  end)
end

return CodySplit
