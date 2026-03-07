-- =============================================================
-- ssh_manager.lua — SSH 会话管理器
-- 封装 brls.SSH.SSHSession，提供：
--   · 连接/断开/重连
--   · 异步轮询读取（定时器驱动）
--   · 事件回调（onData / onError / onDisconnect）
--   · 连接健康检测
-- =============================================================

local Platform = require("platform")

local SSHManager = {}
SSHManager.__index = SSHManager

-- ── 构造函数 ─────────────────────────────────────────────────
function SSHManager.new()
    local self = setmetatable({}, SSHManager)
    self._session     = nil    -- brls.SSH.SSHSession 实例
    self._params      = nil    -- 最近一次连接参数（用于重连）
    self._pollTimer   = nil    -- 轮询定时器句柄
    self._pollInterval= 16     -- 轮询间隔 ms（约 60fps）
    self._connected   = false
    self._reconnecting= false

    -- 事件回调（外部设置）
    self.onData       = nil    -- function(data:string)
    self.onError      = nil    -- function(msg:string)
    self.onDisconnect = nil    -- function()
    self.onConnect    = nil    -- function()

    return self
end

-- ── 连接到远端 ───────────────────────────────────────────────
---@param params table {host, port, user, password, privkey, pubkey, passphrase, timeout}
---@return boolean success, string errMsg
function SSHManager:connect(params)
    -- 清理上次会话
    self:disconnect()

    self._params  = params
    self._session = brls.SSH.newSession()

    -- ① TCP + SSH 握手
    local err = self._session:connect(
        params.host,
        params.port or 22,
        params.timeout or 10000
    )
    if err ~= "" then
        print("[SSH] Connect failed: " .. err)
        self:_fireError("连接失败: " .. err)
        return false, err
    end

    -- ② 认证
    if params.privkey and params.privkey ~= "" then
        -- 公钥认证
        err = self._session:authPublicKey(
            params.user,
            params.pubkey or "",
            params.privkey,
            params.passphrase or ""
        )
    else
        -- 密码认证
        err = self._session:authPassword(params.user, params.password or "")
    end

    if err ~= "" then
        print("[SSH] Auth failed: " .. err)
        self:_fireError("认证失败: " .. err)
        self._session:disconnect()
        return false, err
    end

    -- ③ 打开 PTY Shell
    err = self._session:openShell(
        params.cols or Platform.defaultCols,
        params.rows or Platform.defaultRows
    )
    if err ~= "" then
        print("[SSH] Shell open failed: " .. err)
        self:_fireError("Shell 启动失败: " .. err)
        self._session:disconnect()
        return false, err
    end

    self._connected = true
    print("[SSH] Connected to {}:{} as {}", params.host, params.port or 22, params.user)

    -- ④ 启动轮询定时器
    self:_startPolling()

    -- 触发连接成功回调
    if self.onConnect then
        pcall(self.onConnect)
    end

    return true, ""
end

-- ── 发送数据到远端 Shell ─────────────────────────────────────
---@param data string
---@return boolean success
function SSHManager:send(data)
    if not self._session or not self._connected then
        return false
    end
    local err = self._session:send(data)
    if err ~= "" then
        print("[SSH] Send error: " .. err)
        self:_handleDisconnect()
        return false
    end
    return true
end

-- ── 调整 PTY 窗口大小 ────────────────────────────────────────
function SSHManager:resize(cols, rows)
    if self._session and self._connected then
        self._session:resizePty(cols, rows)
    end
end

-- ── 断开连接 ─────────────────────────────────────────────────
function SSHManager:disconnect()
    self:_stopPolling()
    if self._session then
        self._session:disconnect()
        self._session = nil
    end
    self._connected = false
end

-- ── 重连（使用最近参数）──────────────────────────────────────
function SSHManager:reconnect()
    if self._reconnecting or not self._params then return end
    self._reconnecting = true
    print("[SSH] Reconnecting...")
    self:disconnect()

    -- 延迟 1 秒后重连
    brls.Application.getTimer():start(1000, function()
        self._reconnecting = false
        local ok, err = self:connect(self._params)
        if not ok then
            print("[SSH] Reconnect failed: " .. err)
        end
    end)
end

-- ── 状态查询 ─────────────────────────────────────────────────
function SSHManager:isConnected()
    return self._connected and self._session ~= nil and self._session:isConnected()
end

function SSHManager:getInfo()
    if not self._session then return "" end
    return string.format("%s@%s:%d",
        self._session:getUser(),
        self._session:getHost(),
        self._session:getPort()
    )
end

function SSHManager:getFingerprint()
    if not self._session then return "" end
    return self._session:getFingerprint()
end

-- ── 内部：启动轮询定时器 ─────────────────────────────────────
function SSHManager:_startPolling()
    self:_stopPolling()
    -- brls 定时器每 N ms 回调一次
    -- 注意：在 Borealis Lua 中，使用 brls.Application.setTimer 或类似 API
    -- 这里使用 brls.sync 异步轮询机制
    self._polling = true
    self:_pollOnce()
end

function SSHManager:_stopPolling()
    self._polling = false
    if self._pollTimer then
        -- 取消定时器（若 brls 提供取消接口）
        self._pollTimer = nil
    end
end

-- ── 内部：单次轮询读取 ────────────────────────────────────────
function SSHManager:_pollOnce()
    if not self._polling then return end

    -- 读取数据（非阻塞）
    if self._session and self._connected then
        local data, err = self._session:recv(8192)
        if err == "eof" then
            -- 远端关闭连接
            self:_handleDisconnect()
            return
        elseif err ~= "" and err ~= nil then
            -- 读取错误（非暂无数据）
            print("[SSH] Recv error: " .. tostring(err))
            self:_handleDisconnect()
            return
        elseif data and #data > 0 then
            -- 有数据，触发回调
            if self.onData then
                local ok, e = pcall(self.onData, data)
                if not ok then
                    print("[SSH] onData callback error: " .. tostring(e))
                end
            end
        end
    end

    -- 调度下次轮询（通过 brls 的异步 tick 机制）
    -- 使用 brls.Application.runLoop 或相当的帧回调
    brls.Application.runAsync(self._pollInterval, function()
        self:_pollOnce()
    end)
end

-- ── 内部：处理断开事件 ───────────────────────────────────────
function SSHManager:_handleDisconnect()
    if not self._connected then return end
    print("[SSH] Disconnected from remote.")
    self._connected = false
    self:_stopPolling()
    if self.onDisconnect then
        pcall(self.onDisconnect)
    end
end

-- ── 内部：触发错误回调 ───────────────────────────────────────
function SSHManager:_fireError(msg)
    if self.onError then
        pcall(self.onError, msg)
    end
end

return SSHManager
