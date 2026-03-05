-- Module options:
local always_use_lpeg = false
local register_global_module_table = false
local global_module_name = 'json'

--[==[

David Kolf's JSON module for Lua 5.1 - 5.4

Version 2.8


For the documentation see the corresponding readme.txt or visit
<http://dkolf.de/dkjson-lua/>.

You can contact the author by sending an e-mail to <david@dkolf.de>.


Copyright (C) 2010-2024 David Heiko Kolf

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]==]

-- global dependencies:
local pairs, type, tostring, tonumber, getmetatable, setmetatable, rawset =
      pairs, type, tostring, tonumber, getmetatable, setmetatable, rawset
local error, require, pcall, select = error, require, pcall, select
local floor, huge = math.floor, math.huge
local strrep, gsub, strsub, strbyte, strchar, strfind, strlen, strformat =
      string.rep, string.gsub, string.sub, string.byte, string.char,
      string.find, string.len, string.format
local strmatch = string.match
local concat = table.concat

local json = { version = "dkjson 2.8" }

local json_null = {}
local isArray

local function newencoder()
  local v, nullv
  local i, builder, visited

  local function add(s)
    i = i + 1
    builder[i] = s
  end

  local function preVisit(v)
    if v == nullv then
      return nullv
    end
    local tv = type(v)
    if tv == "table" then
      if visited[v] then
        error("Cannot encode table with recursive reference")
      end
      visited[v] = true
    end
    return tv
  end

  local function postVisit(v)
    if type(v) == "table" then
      visited[v] = nil
    end
  end

  local encodeString = function(s)
    local escapetbl = {
      ['"'] = '\\"',
      ['\\'] = '\\\\',
      ['\b'] = '\\b',
      ['\f'] = '\\f',
      ['\n'] = '\\n',
      ['\r'] = '\\r',
      ['\t'] = '\\t',
    }
    local function subst(ch)
      return escapetbl[ch] or strformat("\\u00%02X", strbyte(ch))
    end
    return '"' .. gsub(s, '[%z\1-\31\"\\]', subst) .. '"'
  end

  local function encode(v, opts)
    local tv = preVisit(v)
    if tv == "string" then
      add(encodeString(v))
    elseif tv == "number" or tv == "boolean" then
      add(tostring(v))
    elseif tv == "table" then
      local first = true
      if isArray(v) then
        add("[")
        for _, v in ipairs(v) do
          if not first then
            add(",")
          end
          first = nil
          encode(v, opts)
        end
        add("]")
      else
        add("{")
        local k, kv
        for k, kv in pairs(v) do
          if type(k) ~= "string" then
            k = tostring(k)
          end
          if not first then
            add(",")
          end
          first = nil
          add(encodeString(k))
          add(":")
          encode(kv, opts)
        end
        add("}")
      end
    elseif tv == "nil" then
      add("null")
    else
      error("Cannot encode value of type " .. tv)
    end
    postVisit(v)
  end

  local function json_encode(data, opts)
    i, builder, visited = 0, {}, {}
    nullv = opts and opts.null
    encode(data, opts)
    return concat(builder)
  end

  return json_encode
end

local function newdecoder()
  local loc, str, escapetbl
  local pos, nullv
  local visited

  local function errorpos(msg)
    error(strformat("%s at position %d", msg, pos))
  end

  local function decode_error(msg)
    errorpos(strformat("Decode error: %s", msg))
  end

  local function scanwhite()
    while strfind(str, "^%s", pos) do
      pos = pos + 1
    end
  end

  local function initescape()
    escapetbl = {
      ['"'] = '"',
      ['\\'] = '\\',
      ['/'] = '/',
      ['b'] = '\b',
      ['f'] = '\f',
      ['n'] = '\n',
      ['r'] = '\r',
      ['t'] = '\t',
    }
  end

  local function scanstring()
    local lastpos = pos + 1
    local surr_a, surr_b
    local i = lastpos
    while true do
      i = strfind(str, "[\"\\]", i)
      if not i then
        decode_error("String not terminated")
      end
      if strsub(str, i, i) == '"' then
        break
      end
      -- Handle escape
      i = i + 1
      local c = strsub(str, i, i)
      if c == "u" then
        local h = strsub(str, i + 1, i + 4)
        local n = tonumber(h, 16)
        if not n then
          decode_error("String escape \\u is not followed by 4 hex digits")
        end
        i = i + 4
      elseif not escapetbl[c] then
        decode_error("Invalid escape character '" .. c .. "'")
      end
    end
    local s = strsub(str, lastpos, i - 1)
    -- Process escape sequences
    s = gsub(s, '\\(.)', function(c)
      local u = escapetbl[c]
      if u then
        return u
      elseif c == "u" then
        return ""
      end
    end)
    s = gsub(s, '\\u(%x%x%x%x)', function(h)
      local n = tonumber(h, 16)
      if n < 0x80 then
        return strchar(n)
      elseif n < 0x800 then
        return strchar(floor(n / 64) + 192, n % 64 + 128)
      else
        return strchar(floor(n / 4096) + 224, floor(n / 64) % 64 + 128, n % 64 + 128)
      end
    end)
    pos = i + 1
    return s
  end

  local scanvalue

  local function scannull()
    pos = pos + 4
    return nullv
  end

  local function scantrue()
    pos = pos + 4
    return true
  end

  local function scanfalse()
    pos = pos + 5
    return false
  end

  local function scannumber()
    local lastpos = pos
    local i = pos
    if strsub(str, i, i) == "-" then
      i = i + 1
    end
    if strsub(str, i, i) == "0" then
      i = i + 1
    else
      i = strfind(str, "^%d+", i)
      if not i then
        decode_error("Number expected")
      end
    end
    if strsub(str, i, i) == "." then
      i = i + 1
      i = strfind(str, "^%d+", i)
      if not i then
        decode_error("Digit expected after decimal point")
      end
    end
    if strfind(str, "^[eE]", i) then
      i = i + 1
      if strfind(str, "^[+-]", i) then
        i = i + 1
      end
      i = strfind(str, "^%d+", i)
      if not i then
        decode_error("Digit expected after exponent")
      end
    end
    local num = tonumber(strsub(str, lastpos, i - 1))
    if not num then
      decode_error("Invalid number")
    end
    pos = i
    return num
  end

  local function scanarray()
    local res = {}
    visited[res] = true
    pos = pos + 1
    scanwhite()
    local first = true
    while strsub(str, pos, pos) ~= "]" do
      if not first then
        if strsub(str, pos, pos) ~= "," then
          decode_error(", or ] expected")
        end
        pos = pos + 1
        scanwhite()
      end
      first = false
      res[#res + 1] = scanvalue()
      scanwhite()
    end
    pos = pos + 1
    visited[res] = nil
    return res
  end

  local function scanobject()
    local res = {}
    visited[res] = true
    pos = pos + 1
    scanwhite()
    local first = true
    while strsub(str, pos, pos) ~= "}" do
      if not first then
        if strsub(str, pos, pos) ~= "," then
          decode_error(", or } expected")
        end
        pos = pos + 1
        scanwhite()
      end
      first = false
      if strsub(str, pos, pos) ~= '"' then
        decode_error("String key expected")
      end
      local key = scanstring()
      scanwhite()
      if strsub(str, pos, pos) ~= ":" then
        decode_error("Colon expected")
      end
      pos = pos + 1
      scanwhite()
      res[key] = scanvalue()
      scanwhite()
    end
    pos = pos + 1
    visited[res] = nil
    return res
  end

  function scanvalue()
    local c = strsub(str, pos, pos)
    if c == '"' then
      return scanstring()
    elseif c == '{' then
      return scanobject()
    elseif c == '[' then
      return scanarray()
    elseif c == 'n' then
      return scannull()
    elseif c == 't' then
      return scantrue()
    elseif c == 'f' then
      return scanfalse()
    else
      return scannumber()
    end
  end

  local function json_decode(js, opts)
    str = js
    pos = 1
    nullv = opts and opts.null
    visited = {}
    if not escapetbl then
      initescape()
    end
    scanwhite()
    local res = scanvalue()
    scanwhite()
    if pos <= strlen(str) then
      decode_error("Trailing characters")
    end
    return res
  end

  return json_decode
end

function isArray(tbl)
  local max = 0
  local count = 0
  for k, v in pairs(tbl) do
    if type(k) == "number" then
      if k > max then max = k end
      count = count + 1
    else
      return false
    end
  end
  if max > count * 2 then
    return false
  end
  return true
end

json.encode = newencoder()
json.decode = newdecoder()
json.null = json_null

if register_global_module_table then
  _G[global_module_name] = json
end

return json
