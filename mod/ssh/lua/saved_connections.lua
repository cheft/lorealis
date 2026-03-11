local json = require("utils/json")

local Platform = require("platform")

local SavedConnections = {}

local _inMemoryConnections = {}

local function getPlatformIo()
    local okPlatform, platform = pcall(function()
        return brls.Application.getPlatform()
    end)

    if okPlatform and platform then
        return platform
    end

    return nil
end

local function getConfigDir()
    if Platform.isSwitch then
        return "sdmc:/config/lorealis/ssh"
    end
    return "./config/ssh"
end

local function getConfigPath()
    return getConfigDir() .. "/connections.json"
end

local function ensureConfigDir()
    local dir = getConfigDir()
    if Platform.isSwitch or package.config:sub(1, 1) == "/" then
        os.execute("mkdir -p '" .. dir .. "'")
    else
        os.execute('if not exist "' .. dir .. '" mkdir "' .. dir .. '"')
    end
end

local function readFile()
    local path = getConfigPath()
    local platform = getPlatformIo()

    if platform and platform.readFile then
        local content = platform:readFile(path)
        if content and content ~= "" then
            return content
        end
    end

    if io then
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            return content
        end
    end

    return nil
end

local function writeFile(content)
    ensureConfigDir()

    local path = getConfigPath()
    local platform = getPlatformIo()

    if platform and platform.writeFile then
        return platform:writeFile(path, content)
    end

    if io then
        local file = io.open(path, "w")
        if not file then
            return false
        end
        file:write(content)
        file:close()
        return true
    end

    return false
end

local function normalize(conn)
    local port = tonumber(conn.port) or 22
    local endpoint = conn.endpoint or string.format("%s@%s:%d", conn.user, conn.host, port)
    return {
        endpoint = endpoint,
        name = conn.name or endpoint,
        user = conn.user,
        host = conn.host,
        port = port,
    }
end

function SavedConnections.load()
    local content = readFile()
    if not content or content == "" then
        return _inMemoryConnections
    end

    local okDecode, decoded, posOrErr, decodeErr = pcall(json.decode, content)
    if not okDecode then
        print("[SSH] Failed to decode connections.json: " .. tostring(decoded))
        return _inMemoryConnections
    end

    if decoded == nil then
        local errText = tostring(decodeErr or posOrErr or "unknown decode error")
        print("[SSH] Invalid connections.json: " .. errText)
        return _inMemoryConnections
    end

    if type(decoded) ~= "table" then
        return _inMemoryConnections
    end

    local list = decoded.connections or decoded
    if type(list) ~= "table" then
        return _inMemoryConnections
    end

    local out = {}
    for _, conn in ipairs(list) do
        if type(conn) == "table" and conn.host and conn.user then
            table.insert(out, normalize(conn))
        end
    end

    _inMemoryConnections = out
    return out
end

function SavedConnections.save(list)
    local normalized = {}
    for _, conn in ipairs(list or {}) do
        table.insert(normalized, normalize(conn))
    end

    _inMemoryConnections = normalized
    local content = json.encode({ version = 2, connections = normalized })
    if not content then
        return false
    end

    return writeFile(content)
end

function SavedConnections.validate(conn)
    if not conn or not conn.host or conn.host == "" then
        return false, "主机地址不能为空"
    end
    if not conn.user or conn.user == "" then
        return false, "用户名不能为空"
    end

    local port = tonumber(conn.port) or 22
    if port < 1 or port > 65535 then
        return false, "端口号无效 (1-65535)"
    end

    return true, ""
end

function SavedConnections.upsert(conn)
    local valid, err = SavedConnections.validate(conn)
    if not valid then
        return SavedConnections.load(), false, false, err
    end

    local normalized = normalize(conn)
    local list = SavedConnections.load()
    local existed = false

    for index, item in ipairs(list) do
        if item.endpoint == normalized.endpoint then
            table.remove(list, index)
            existed = true
            break
        end
    end

    table.insert(list, 1, normalized)
    while #list > 50 do
        table.remove(list)
    end

    local saved = SavedConnections.save(list)
    return list, existed, saved
end

function SavedConnections.remove(index)
    local list = SavedConnections.load()
    table.remove(list, index)
    local saved = SavedConnections.save(list)
    return list, saved
end

function SavedConnections.removeByEndpoint(endpoint)
    local list = SavedConnections.load()
    local removed = false

    for index, conn in ipairs(list) do
        if conn.endpoint == endpoint then
            table.remove(list, index)
            removed = true
            break
        end
    end

    local saved = SavedConnections.save(list)
    return list, removed, saved
end

function SavedConnections.findByName(name)
    for _, conn in ipairs(SavedConnections.load()) do
        if conn.name == name or conn.endpoint == name then
            return conn
        end
    end
    return nil
end

return SavedConnections
