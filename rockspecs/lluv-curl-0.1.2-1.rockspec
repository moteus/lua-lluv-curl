package = "lluv-curl"
version = "0.1.2-1"

source = {
  url = "https://github.com/moteus/lua-lluv-curl/archive/v0.1.2.zip",
  dir = "lua-lluv-curl-0.1.2",
}

description = {
  summary    = "Make asyncronus requests using libuv and libcurl",
  homepage   = "https://github.com/moteus/lua-lluv-curl",
  license    = "MIT/X11",
  maintainer = "Alexey Melnichuk",
  detailed   = [[
  ]],
}

dependencies = {
  "lua >= 5.1, < 5.4",
  "lluv > 0.1.1",
  "lua-curl",
  "eventemitter",
}

build = {
  copy_directories = {'examples'},

  type = "builtin",

  modules = {
    ["lluv.curl"           ] = "src/lua/lluv/curl.lua",
  }
}
