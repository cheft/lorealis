-- =============================================================
-- saved_connections.lua — 连接配置持久化
-- 使用 JSON 格式将连接列表保存到本地文件
-- Switch: romfs 只读，写入路径使用 sdmc:/config/lorealis/ssh/
-- Desktop: 使用 ./config/ssh/connections.json
-- =============================================================

-- 尝试加载 dkjson（包内自带）
local json
local ok, j = pcall(require, "utils/dkjson")
if ok then
    json = j
else
    -- fallback: 极简 json（仅支持简单 key-value）
    json = {
        encode = function(t)
            -- 简单序列化（仅用于备用）
            local s = "{"
            for k, v in pairs(t) do
                local vs = type(v) == "string" and ('"' .. v:gsub('"', '\\"') .. '"')
                        or type(v) == "number" and tostring(v)
                        or type(v) == "boolean" and tostring(v)
                        or "null"
                s = s .. '"' .. tostring(k) .. '":' .. vs .. ","
            end
            return s:sub(1, -2) .. "}"
        end,
        decode = function(s) return {} end,
    }
end

-- ── 路径配置 ─────────────────────────────────────────────────
local Platform = require("platform")

local function getConfigDir()
    if Platform.isSwitch then
        return "sdmc:/config/lorealis/ssh"
    else
        return "./config/ssh"
    end
end

local function getConfigPath()
    return getConfigDir() .. "/connections.json"
end

-- ── 公共 API ─────────────────────────────────────────────────
local SavedConnections = {}

-- ── 加载连接列表 ─────────────────────────────────────────────
---@return table  连接列表（array of connection）
function SavedConnections.load()
    local path = getConfigPath()
    local f = io.open(path, "r")
    if not f then
        return {}
    end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return {} end
    local ok2, data = pcall(json.decode, content)
    if not ok2 or type(data) ~= "table" then
        return {}
    end
    return data.connections or {}
end

-- ── 保存连接列表 ─────────────────────────────────────────────
---@param list table  连接列表
---@return boolean  是否保存成功
function SavedConnections.save(list)
    -- 确保目录存在（跨平台 mkdir）
    local dir = getConfigDir()
    -- 使用 os.execute 创建目录（跨平台）
    if Platform.isSwitch then
        os.execute("mkdir -p '" .. dir .. "'")
    else
        os.execute("mkdir -p \"" .. dir .. "\" 2>nul || mkdir \"" .. dir:gsub("/", "\\") .. "\"")
    end

    local path = getConfigPath()
    local f = io.open(path, "w")
    if not f then
        brls.Logger.error("[SSH] Cannot write config: " .. path)
        return false
    end
    local data = {connections = list, version = 1}
    local content = json.encode(data)
    f:write(content)
    f:close()
    return true
end

-- ── 添加或更新连接 ────────────────────────────────────────────
---@param conn table {name, host, port, user, password?, privkey?, pubkey?, tags?}
---@return table  更新后的列表
function SavedConnections.upsert(conn)
    local list = SavedConnections.load()
    -- 按 name + host 去重
    local found = false
    for i, c in ipairs(list) do
        if c.name == conn.name and c.host == conn.host then
            list[i] = conn
            found = true
            break
        end
    end
    if not found then
        table.insert(list, 1, conn)  -- 最新添加放在最前
    end
    -- 最多保存 50 条
    while #list > 50 do
        table.remove(list)
    end
    SavedConnections.save(list)
    return list
end

-- ── 删除连接 ─────────────────────────────────────────────────
---@param idx integer  列表索引（1-based）
---@return table  更新后的列表
function SavedConnections.remove(idx)
    local list = SavedConnections.load()
    table.remove(list, idx)
    SavedConnections.save(list)
    return list
end

-- ── 查找连接 ─────────────────────────────────────────────────
---@param name string
---@return table|nil
function SavedConnections.findByName(name)
    local list = SavedConnections.load()
    for _, c in ipairs(list) do
        if c.name == name then return c end
    end
    return nil
end

-- ── 连接配置验证 ─────────────────────────────────────────────
---@param conn table
---@return boolean, string  (valid, errorMsg)
function SavedConnections.validate(conn)
    if not conn.host or conn.host == "" then
        return false, "主机地址不能为空"
    end
    if not conn.user or conn.user == "" then
        return false, "用户名不能为空"
    end
    local port = tonumber(conn.port) or 22
    if port < 1 or port > 65535 then
        return false, "端口号无效 (1-65535)"
    end
    if (not conn.password or conn.password == "") and
       (not conn.privkey  or conn.privkey  == "") then
        return false, "需要提供密码或私钥"
    end
    return true, ""
end

return SavedConnections
