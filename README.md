# lua-lluv-curl
Make asyncronus requests using libuv and libcurl

Project is in experimental stage. I am not sure about good API.

### Exaples

Implementation of [uvwget](http://nikhilm.github.io/uvbook/utilities.html#external-i-o-with-polling)
example from [An Introduction to libuv](http://nikhilm.github.io/uvbook/index.html) book.

```Lua
local curl = require "lluv.curl"

-- Create Request object wich allows up to 10 parallel request
local request = curl.Request{
  concurent = 10;
}

for i, url in ipairs(arg) do
  local path, file = tostring(i) .. '.download'
  -- this function actually put reques in queue
  -- and returns special `task` object.
  -- Also it is possible pass any `cURL` options.
  request:perform(url, {followlocation = true})
    -- handle input data
    :on('data', function(_, _, data)
      file = file or assert(io.open(path, 'wb+'))
      file:write(data)
    end)
    -- Some error (e.g. SSL fail)
    :on('error', function(_, _, err)
      if file then file:close() end
      io.stderr:write(url ..  ' - FAIL: ' .. tostring(err) .. '\n')
    end)
    -- Success finish
    :on('done', function(_, _, code)
      if file then file:close() end
      io.stdout:write(url ..  ' - DONE: ' .. tostring(code) .. '; Path: ' ..path .. '\n')
    end)
  i = i + 1
end
```
