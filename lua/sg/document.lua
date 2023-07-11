local document = {}

--- Determines if buffer is useful
---@param bufnr any
document.is_useful = function(bufnr)
  local bo = vim.bo[bufnr]
  if bo.buflisted == 0 then
    return false
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if not name or name == "" then
    return false
  end

  return true
end

return document
