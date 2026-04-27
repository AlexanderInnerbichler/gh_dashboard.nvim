local M = {}

local MAX_CONCURRENT = 8
local in_flight = 0
local queue     = {}

local function dispatch(args, callback)
  in_flight = in_flight + 1
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      in_flight = in_flight - 1
      if #queue > 0 then
        local job = table.remove(queue, 1)
        dispatch(job.args, job.callback)
      end
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

--- Run a gh CLI command asynchronously and decode the JSON response.
--- Requests are queued when MAX_CONCURRENT (8) are already in flight.
--- callback(err, data): err is a string on failure, nil on success.
function M.run(args, callback)
  if in_flight < MAX_CONCURRENT then
    dispatch(args, callback)
  else
    table.insert(queue, { args = args, callback = callback })
  end
end

--- Run a gh CLI command with up to 2 retries on failure (exponential backoff: 1s, 2s).
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

--- Check the current GitHub API rate limit.
--- callback(info | nil): info = {core, search, reset} or nil on error.
--- Bypasses the request queue — intended as a lightweight meta-call.
function M.check_rate_limit(callback)
  vim.system(
    { "gh", "api", "rate_limit", "--jq",
      "{core:.resources.core.remaining,search:.resources.search.remaining,reset:.resources.core.reset}" },
    { text = true },
    function(r)
      vim.schedule(function()
        if r.code ~= 0 then callback(nil) return end
        local ok, d = pcall(vim.fn.json_decode, r.stdout)
        callback(ok and d or nil)
      end)
    end
  )
end

return M
