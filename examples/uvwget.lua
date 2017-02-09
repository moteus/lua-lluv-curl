io.stdout:setvbuf'no';io.stderr:setvbuf'no';
package.path = "..\\src\\lua\\?.lua;" .. package.path

local uv           = require "lluv"
local curl         = require "lluv.curl"

-- need at least one new url
if not arg[1] then
  io.stdout:write('no url provided')
  os.exit(-1)
end

local request = curl.Request{
  concurent = 10;
}

for i, url in ipairs(arg) do
  local path, file = tostring(i) .. '.download'
  request:perform(url, {followlocation = true})
    :on('data', function(_, _, data)
      file = file or assert(io.open(path, 'wb+'))
      file:write(data)
    end)
    :on('error', function(_, _, err)
      if file then file:close() end
      io.stderr:write(url ..  ' - FAIL: ' .. tostring(err) .. '\n')
    end)
    :on('done', function(_, _, code)
      if file then file:close() end
      io.stdout:write(url ..  ' - DONE: ' .. tostring(code) .. '; Path: ' ..path .. '\n')
    end)
  i = i + 1
end

uv.run()


