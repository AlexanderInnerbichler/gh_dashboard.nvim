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

--- Run a gh CLI command with up to 2 retries on failure (exponential backoff: 1s, 2s).
--- callback(err, data): same contract as M.run.
function M.run_with_retry(args, callback, attempts)
  attempts = attempts or 0
  M.run(args, function(err, data)
    if err and attempts < 2 then
      vim.defer_fn(function()
        M.run_with_retry(args, callback, attempts + 1)
      end, 2 ^ attempts * 1000)
    else
      callback(err, data)
    end
  end)
end

return M
