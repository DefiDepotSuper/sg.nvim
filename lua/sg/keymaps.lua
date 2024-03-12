local M = {}

local store = {}

M.map = function(bufnr, mode, key, desc, cb)
  if type(bufnr) == "table" then
    for _, buf in ipairs(bufnr) do
      M.map(buf, mode, key, desc, cb)
    end

    return
  end

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if type(mode) == "table" then
    for _, m in ipairs(mode) do
      M.map(bufnr, m, key, desc, cb)
    end

    return
  end

  if not store[bufnr] then
    store[bufnr] = {
      maps = {},
    }

    vim.api.nvim_buf_attach(bufnr, false, {
      on_detach = function()
        store[bufnr] = nil
      end,
    })
  end

  table.insert(store[bufnr].maps, { mode = mode, key = key, desc = desc })

  vim.keymap.set(mode, key, cb, {
    buffer = bufnr,
    desc = desc,
  })
end

M.help_lines = function(bufnr)
  local maps = store[bufnr]
  if not maps then
    return {}
  end

  local sorted_maps = {}
  for _, map in ipairs(maps.maps) do
    if not sorted_maps[map.mode] then
      sorted_maps[map.mode] = {}
    end

    table.insert(sorted_maps[map.mode], map)
  end

  local lines = { "mode |   key  | description" }
  for _, map_list in pairs(sorted_maps) do
    for _, map in ipairs(map_list) do
      local line = string.format("%s    | %6s | %s", map.mode, map.key, map.desc)
      table.insert(lines, line)
    end
  end

  return lines
end

M.help = function(bufnr)
  local maps = store[bufnr]
  if not maps then
    return
  end

  local lines = M.help_lines(bufnr)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)

  local keymap_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(keymap_buf, 0, -1, true, lines)

  local win = vim.api.nvim_open_win(keymap_buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = "Cody Keymaps",
    col = math.floor(vim.o.columns * 0.1),
    row = math.floor(vim.o.lines * 0.1),
    width = width,
    height = height,
    noautocmd = true,
  })

  local close = function()
    pcall(vim.api.nvim_buf_delete, keymap_buf, { force = true })
    pcall(vim.api.nvim_win_close, win, true)

    return true
  end

  vim.keymap.set("n", "q", close, { buffer = keymap_buf })
  vim.keymap.set("n", "<esc>", close, { buffer = keymap_buf })

  -- I don't think there is a better way to do this.
  --    We schedule this so that we can enter the window first,
  --    and then allow the autocmds to run
  vim.schedule(function()
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter", "ModeChanged" }, {
      callback = close,
    })
  end)
end

M.del = function(bufnr, mode, key)
  vim.keymap.del(mode, key, { buffer = bufnr })

  store[bufnr].maps = vim.tbl_filter(function(map)
    return map.mode ~= mode
      or vim.api.nvim_replace_termcodes(map.key, true, false, true)
        ~= vim.api.nvim_replace_termcodes(key, true, false, true)
  end, store[bufnr].maps)
end

return M
