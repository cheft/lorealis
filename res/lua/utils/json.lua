-- Simple JSON encoder/decoder for Lua
-- Based on public domain implementations

local json = {}

-- Encode a Lua value to JSON string
local function encode_value(val, depth)
    depth = depth or 0
    local t = type(val)
    
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then -- nan
            return "null"
        elseif val == math.huge then
            return "null"
        elseif val == -math.huge then
            return "null"
        end
        return tostring(val)
    elseif t == "string" then
        local result = '"'
        for i = 1, #val do
            local c = val:sub(i, i)
            local b = c:byte()
            if c == '"' then
                result = result .. '\\"'
            elseif c == '\\' then
                result = result .. '\\\\'
            elseif c == '\b' then
                result = result .. '\\b'
            elseif c == '\f' then
                result = result .. '\\f'
            elseif c == '\n' then
                result = result .. '\\n'
            elseif c == '\r' then
                result = result .. '\\r'
            elseif c == '\t' then
                result = result .. '\\t'
            elseif b < 32 then
                result = result .. string.format("\\u00%02x", b)
            else
                result = result .. c
            end
        end
        return result .. '"'
    elseif t == "table" then
        -- Check if it's an array
        local is_array = true
        local max_index = 0
        local count = 0
        for k, v in pairs(val) do
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                is_array = false
                break
            end
            if k > max_index then max_index = k end
            count = count + 1
        end
        if max_index > count * 2 then
            is_array = false
        end
        
        local parts = {}
        if is_array then
            for i = 1, max_index do
                parts[i] = encode_value(val[i], depth + 1)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local i = 1
            for k, v in pairs(val) do
                if type(k) ~= "string" then
                    k = tostring(k)
                end
                parts[i] = encode_value(k, depth + 1) .. ":" .. encode_value(v, depth + 1)
                i = i + 1
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

-- Decode JSON string to Lua value
local function decode_value(str, pos)
    pos = pos or 1
    pos = str:match("^%s*()", pos) or pos
    local c = str:sub(pos, pos)
    
    if c == '"' then
        -- String
        local result = ""
        pos = pos + 1
        while pos <= #str do
            local ch = str:sub(pos, pos)
            if ch == '"' then
                pos = pos + 1
                return result, pos
            elseif ch == '\\' then
                pos = pos + 1
                ch = str:sub(pos, pos)
                if ch == '"' then result = result .. '"'
                elseif ch == '\\' then result = result .. '\\'
                elseif ch == '/' then result = result .. '/'
                elseif ch == 'b' then result = result .. '\b'
                elseif ch == 'f' then result = result .. '\f'
                elseif ch == 'n' then result = result .. '\n'
                elseif ch == 'r' then result = result .. '\r'
                elseif ch == 't' then result = result .. '\t'
                elseif ch == 'u' then
                    local hex = str:sub(pos + 1, pos + 4)
                    pos = pos + 4
                    local n = tonumber(hex, 16)
                    if n < 128 then
                        result = result .. string.char(n)
                    elseif n < 2048 then
                        result = result .. string.char(math.floor(n / 64) + 192, n % 64 + 128)
                    else
                        result = result .. string.char(math.floor(n / 4096) + 224, math.floor(n / 64) % 64 + 128, n % 64 + 128)
                    end
                else
                    result = result .. ch
                end
            else
                result = result .. ch
            end
            pos = pos + 1
        end
        error("Unterminated string")
    elseif c == '{' then
        -- Object
        local obj = {}
        pos = pos + 1
        pos = str:match("^%s*()", pos) or pos
        if str:sub(pos, pos) == '}' then
            return obj, pos + 1
        end
        while true do
            local key
            key, pos = decode_value(str, pos)
            if type(key) ~= "string" then
                error("Object key must be a string")
            end
            pos = str:match("^%s*()", pos) or pos
            if str:sub(pos, pos) ~= ':' then
                error("Expected ':' after object key")
            end
            pos = pos + 1
            local val
            val, pos = decode_value(str, pos)
            obj[key] = val
            pos = str:match("^%s*()", pos) or pos
            local sep = str:sub(pos, pos)
            if sep == '}' then
                pos = pos + 1
                break
            elseif sep ~= ',' then
                error("Expected ',' or '}' in object")
            end
            pos = pos + 1
        end
        return obj, pos
    elseif c == '[' then
        -- Array
        local arr = {}
        pos = pos + 1
        pos = str:match("^%s*()", pos) or pos
        if str:sub(pos, pos) == ']' then
            return arr, pos + 1
        end
        local idx = 1
        while true do
            local val
            val, pos = decode_value(str, pos)
            arr[idx] = val
            idx = idx + 1
            pos = str:match("^%s*()", pos) or pos
            local sep = str:sub(pos, pos)
            if sep == ']' then
                pos = pos + 1
                break
            elseif sep ~= ',' then
                error("Expected ',' or ']' in array")
            end
            pos = pos + 1
        end
        return arr, pos
    elseif c == 't' and str:sub(pos, pos + 3) == 'true' then
        return true, pos + 4
    elseif c == 'f' and str:sub(pos, pos + 4) == 'false' then
        return false, pos + 5
    elseif c == 'n' and str:sub(pos, pos + 3) == 'null' then
        return nil, pos + 4
    elseif c == '-' or (c >= '0' and c <= '9') then
        -- Number
        local num_str = str:match("^%-?%d+%.?%d*[eE]?[+-]?%d*", pos)
        if not num_str then
            error("Invalid number")
        end
        local num = tonumber(num_str)
        if not num then
            error("Invalid number: " .. num_str)
        end
        return num, pos + #num_str
    else
        error("Unexpected character: '" .. c .. "' at position " .. pos)
    end
end

function json.encode(val)
    return encode_value(val)
end

function json.decode(str)
    if type(str) ~= "string" then
        error("JSON decode expects a string, got " .. type(str))
    end
    local result, pos = decode_value(str, 1)
    -- Check for trailing data (except whitespace)
    local trailing = str:match("^%s*(.+)$", pos)
    if trailing and #trailing > 0 then
        error("Trailing data after JSON: " .. trailing:sub(1, 20))
    end
    return result
end

json.null = {}

return json
