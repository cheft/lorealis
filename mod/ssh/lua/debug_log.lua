-- =============================================================
-- debug_log.lua - file logger for SSH module diagnostics
-- Switch:  sdmc:/brls.log
-- Desktop: ./brls.log
-- =============================================================

local Platform = require("platform")

local DebugLog = {}

local function getLogPath()
    if Platform.isSwitch then
        return "sdmc:/brls.log"
    end
    return "./brls.log"
end

local function ensureDir()
    local path = getLogPath()
    local dir = path:match("(.+)/[^/]+$")
    if not dir then return end

    local platform = brls.Application.getPlatform()
    if platform and platform.mkdir then
        pcall(function()
            platform:mkdir(dir)
        end)
    end
end

local function readAll(path)
    local platform = brls.Application.getPlatform()
    if not platform or not platform.readFile then return "" end

    local ok, content = pcall(function()
        return platform:readFile(path)
    end)
    if ok and type(content) == "string" then
        return content
    end
    return ""
end

function DebugLog.path()
    return getLogPath()
end

function DebugLog.clear()
    ensureDir()
    local platform = brls.Application.getPlatform()
    if not platform or not platform.writeFile then return false end
    local ok = pcall(function()
        platform:writeFile(getLogPath(), "")
    end)
    return ok and true or false
end

function DebugLog.append(msg)
    ensureDir()
    local platform = brls.Application.getPlatform()
    if not platform or not platform.writeFile then return false end

    local path = getLogPath()
    local ts = "0000-00-00 00:00:00"
    if os and os.date then
        ts = os.date("%Y-%m-%d %H:%M:%S")
    end

    local line = string.format("[%s] %s\n", ts, tostring(msg))
    local old = readAll(path)

    -- Keep only the tail so the log file does not grow unbounded.
    local cap = 128 * 1024
    if #old > cap then
        old = old:sub(#old - cap + 1)
    end

    local ok = pcall(function()
        platform:writeFile(path, old .. line)
    end)
    return ok and true or false
end

return DebugLog
