local M = {}

--- Run a gh CLI command asynchronously and decode the JSON response.
--- callback(err, data): err is a string on failure, nil on success;
---                      data is the decoded Lua table on success, nil on failure.
function M.run(args, callback)
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(result.stderr or "gh error", nil)
        return
      end
      local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
      if not ok then
        callback("json decode error: " .. tostring(decoded), nil)
        return
      end
      callback(nil, decoded)
    end)
  end)
end

return M
