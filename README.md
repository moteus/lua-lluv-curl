# lua-lluv-curl
Make asyncronus requests using libuv and libcurl

Project is in experimental stage. I am not sure about good API.

### Exaples

Implementation of [uvwget](http://nikhilm.github.io/uvbook/utilities.html#external-i-o-with-polling)
example from [An Introduction to libuv](http://nikhilm.github.io/uvbook/index.html) book.

```Lua
local curl = require "lluv.curl"

-- Create Request object
local request = curl.Request{
  -- Allow up to 10 parallel requests
  concurent = 10;
  -- Default options for easy handles
  defaults = { -- this is valuses used by defualt
    fresh_connect = true;
    forbid_reuse  = true;
  };
}

for i, url in ipairs(arg) do
  local path, file = tostring(i) .. '.download'
  -- this function actually put reques in queue
  -- and returns special `task` object.
  -- Also it is possible pass any `cURL` options.
  request:perform(url, {followlocation = true}, function(task) task
    -- Here we can configure created task object before it will be used

    -- calls after configuration done but before actually start perform
    :on('start', function(_, _, easy)
      file = assert(io.open(path, 'wb+'))
      easy:setopt_writefunction(file)
    end)
    -- calls in any case when task is finish
    :on('close', function()
      if file then file:close() end
    end)
     -- Some error (e.g. SSL fail or user interupted)
    :on('error', function(_, _, err)
      io.stderr:write(url ..  ' - FAIL: ' .. tostring(err) .. '\n')
    end)
    -- This means that request done without any error
    :on('done', function(_, _, easy)
      local code = easy:getinfo_response_code()
      io.stdout:write(url ..  ' - DONE: ' .. tostring(code) .. '; Path: ' ..path .. '\n')
    end)
  end)
  i = i + 1
end
```
