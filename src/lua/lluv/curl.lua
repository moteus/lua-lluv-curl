local curl         = require "cURL"
local uv           = require "lluv"
local ut           = require "lluv.utils"
local EventEmitter = require "EventEmitter".EventEmitter

local function super(self, method, ...)
  if self.__base[method] then
    return self.__base[method](self, ...)
  end
end

local ACTION_NAMES = {
  [curl.POLL_IN     ] = "POLL_IN";
  [curl.POLL_INOUT  ] = "POLL_INOUT";
  [curl.POLL_OUT    ] = "POLL_OUT";
  [curl.POLL_NONE   ] = "POLL_NONE";
  [curl.POLL_REMOVE ] = "POLL_REMOVE";
}

local POLL_IO_FLAGS = {
  [ curl.POLL_IN    ] = uv.READABLE;
  [ curl.POLL_OUT   ] = uv.WRITABLE;
  [ curl.POLL_INOUT ] = uv.READABLE + uv.WRITABLE;
}

local EVENT_NAMES = {
  [ uv.READABLE               ] = "READABLE";
  [ uv.WRITABLE               ] = "WRITABLE";
  [ uv.READABLE + uv.WRITABLE ] = "READABLE + WRITABLE";
}

local FLAGS = {
  [ uv.READABLE               ] = curl.CSELECT_IN;
  [ uv.WRITABLE               ] = curl.CSELECT_OUT;
  [ uv.READABLE + uv.WRITABLE ] = curl.CSELECT_IN + curl.CSELECT_OUT;
}

local BasicTask = ut.class(EventEmitter) do

function BasicTask:__init(url, opt)
  super(self, '__init')

  self._url = url
  self._opt = opt

  return self
end

function BasicTask:start(handle)
  local ok, err = handle:setopt{
    url           = self._url;
    fresh_connect = true;
    forbid_reuse  = true;

    writefunction = function(...)
      self:emit('data', ...)
      return true
    end;

    headerfunction = function(...)
      self:emit('header', ...)
      return true
    end;
  }
  if not ok then return nil, err end

  if self._opt then
    local ok, err = handle:setopt(self._opt)
    if not ok then return nil, err end
  end

  self:emit('start', handle)

  return true
end

function BasicTask:close(err, handle)
  if err then
    self:emit('error', err)
  elseif not handle then
    self:emit('error', 'interrupted')
  else
    self:emit('done', handle)
  end
  self:emit('close')
end

end

local Context = ut.class() do

function Context:__init(fd)
  self._fd        = assert(fd)
  self._poll      = uv.poll_socket(fd)
  self._poll.data = {context = self}

  assert(self._poll:fileno() == fd)

  return self
end

function Context:close()
  if self._poll then
    self._poll.data = nil
    self._poll:close()
  end
  self._poll, self._fd = nil
end

function Context:poll(...)
  self._poll:start(...)
end

function Context:fileno()
  return self._fd
end

end

local cUrlRequest = ut.class(EventEmitter) do

function cUrlRequest:__init(options)
  super(self, '__init', {wildcard = true, delimiter = '::'})

  options = options or {}

  self._MAX_REQUESTS  = options.concurent or 1 -- Number of parallel request
  self._timer         = uv.timer()
  self._qtask         = ut.Queue.new()         -- wait tasks
  self._qfree         = ut.Queue.new()         -- avaliable easy handles
  self._qeasy         = {}                     -- all easy handles
  self._easy_defaults = options.defaults or {  -- default options for easy handles
    fresh_connect = true;
    forbid_reuse  = true;
  }

  self._multi = curl.multi()
  self._multi:setopt_timerfunction (self._on_curl_timeout, self)
  self._multi:setopt_socketfunction(self._on_curl_action,  self)

  self._on_libuv_poll = function(poller, err, events)
    self:emit('uv::poll', poller, err, EVENT_NAMES[events] or events)

    local flags = assert(FLAGS[events], ("unknown event:" .. events))

    local context = poller.data.context

    self._multi:socket_action(context:fileno(), flags)

    self:_curl_check_multi_info()
  end

  self._on_libuv_timeout = function(timer)
    self:emit('uv::timeout', poller, err, EVENT_NAMES[events] or events)

    self._multi:socket_action()

    self:_curl_check_multi_info()
  end

  return self
end

function cUrlRequest:close(err)
  for i, easy in ipairs(self._qeasy) do
    self._multi:remove_handle(easy)

    if easy.data then
      local context = easy.data.context
      if context then context:close() end

      local task = easy.data.task
      if task then task:close(err, easy) end
    end

    easy:close()
  end

  while true do
    local task = self._qtask:pop()
    if not task then break end
    task:close(err)
  end

  self._multi:close()
  self._timer:close()

  self._timer, self._qeasy, self._multi, self._qtask, self._qfree = nil

  self:emit('close')
end

function cUrlRequest:add(task)
  self._qtask:push(task)
  self:_proceed_queue()
  return task
end

function cUrlRequest:perform(url, opt, cb)
  local task
  if type(url) == 'string' then
    task = BasicTask.new(url, (type(opt) == 'table') and opt)
    cb = (type(opt) == 'function') and opt or cb
    if cb then cb(task) end
  else
    task = url
  end

  return self:add(task)
end

function cUrlRequest:_next_handle()
  if not self._qfree:empty() then
    return assert(self._qfree:pop())
  end

  if #self._qeasy >= self._MAX_REQUESTS then
    return
  end

  local handle = assert(curl.easy())
  self._qeasy[#self._qeasy + 1] = handle

  return handle
end

function cUrlRequest:_proceed_queue()
  while true do
    if self._qtask:empty() then return end

    local task = assert(self._qtask:peek())

    local handle = self:_next_handle()
    if not handle then return end

    assert(task == self._qtask:pop())

    local ok, res, err
    ok, res = handle:setopt( self._easy_defaults )
    if ok then
      ok, res, err = pcall(task.start, task, handle)
    end

    if not (ok and res) then
      handle:reset().data = nil
      self._qfree:push(handle)
      if not ok then err = res end
      task:close(res)
    else
      handle.data = {
        task = task
      }
      self._multi:add_handle(handle)
    end
  end
end

function cUrlRequest:_on_curl_timeout(ms)
  self:emit("curl::timeout", ms)

  if not self._timer:active() then
    if ms <= 0 then ms = 1 end

    self._timer:start(ms, 0, self._on_libuv_timeout)
  end
end

function cUrlRequest:_on_curl_action(easy, fd, action)
  local ok, err = pcall(function()
    self:emit("curl::socket", easy, fd, ACTION_NAMES[action] or action)

    local context = easy.data.context

    local flag = POLL_IO_FLAGS[action]
    if flag then
      if not context then
        context = Context.new(fd)
        easy.data.context = context
      end
      context:poll(flag, self._on_libuv_poll)
    elseif action == curl.POLL_REMOVE then
      if context then
        easy.data.context = nil
        context:close()
      end
    end
  end)

  if not ok then uv.defer(function() error(err) end) end
end

function cUrlRequest:_curl_check_multi_info()
  local multi = self._multi
  while true do
    local easy, ok, err = multi:info_read(true)

    if not easy then
      self:close(err)
      return self:emit('error', err)
    end

    if easy == 0 then break end

    local context = easy.data.context
    if context then context:close() end
    easy.data.context = nil

    local task = easy.data.task

    if ok then err = nil end
    task:close(err, easy)

    easy:reset().data = nil
    self._qfree:push(easy)
  end

  self:_proceed_queue()
end

end

return {
  Request = cUrlRequest.new
}