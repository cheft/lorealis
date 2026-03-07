-- =============================================================
-- connection_view.lua — SSH 连接管理 UI（简化版本）
-- 仅使用已知可用的 Borealis Lua API
-- =============================================================

local Platform        = require("platform")
local SavedConnections= require("saved_connections")
local SSHManager      = require("ssh_manager")
local TerminalView    = require("terminal_view")

local ConnectionView = {}
ConnectionView.__index = ConnectionView

-- ── 构造函数 ─────────────────────────────────────────────────
function ConnectionView.new()
    local self = setmetatable({}, ConnectionView)

    self._ssh          = SSHManager.new()
    self._terminal     = TerminalView.new(self._ssh)
    self._connections  = SavedConnections.load()
    self._activity     = nil

    -- 配置 SSH 回调
    self._ssh.onData = function(data)
        self._terminal:feedData(data)
    end
    self._ssh.onConnect = function()
        self._terminal:setStatus("已连接: " .. self._ssh:getInfo(), 80, 220, 80)
        self:_showTerminal()
    end
    self._ssh.onDisconnect = function()
        self._terminal:setStatus("已断开连接", 220, 80, 80)
        brls.Application.runAsync(2000, function()
            self:_showConnectionList()
        end)
    end
    self._ssh.onError = function(msg)
        local dialog = brls.Dialog.new("SSH 错误: " .. msg)
        dialog:addButton("确定", function() end)
        dialog:open()
        print("[SSH] " .. msg)
    end

    return self
end

function ConnectionView:setActivity(activity)
    self._activity = activity
end

-- ── 显示连接列表页 ───────────────────────────────────────────
function ConnectionView:show()
    self._connections = SavedConnections.load()
    self:_showConnectionList()
end

-- ── 内部：显示连接列表（极简版本）────────────────────────
function ConnectionView:_showConnectionList()
    -- 使用 Dialog 作为主界面（简化实现）
    local title = "SSH 客户端"
    if #self._connections == 0 then
        title = "SSH 客户端 - 无连接"
    else
        title = "SSH 客户端 - " .. #self._connections .. " 个连接"
    end
    local dialog = brls.Dialog.new(title)

    -- 为每个连接添加按钮
    for i, conn in ipairs(self._connections) do
        local btnText = (conn.name or conn.host) .. " (" .. conn.user .. "@" .. conn.host .. ")"
        dialog:addButton(btnText, function()
            dialog:close()
            self:_doConnect(conn)
        end)
    end

    -- 新建连接按钮
    dialog:addButton("+ 新建连接", function(v)
        local ok, err = pcall(function()
            self:_showConnectForm()
        end)
        if not ok then
            print("[SSH] Error showing connect form: " .. tostring(err))
        end
        return true
    end)

    dialog:open()
end

-- ── 内部：显示连接表单 ──────────────────────────────────────
function ConnectionView:_showConnectForm()
    local dialog = brls.Dialog.new("新建 SSH 连接")

    -- 使用 InputCell 输入（如果可用）
    local ok, inputHost = pcall(function()
        return brls.InputCell.new()
    end)

    if ok and inputHost then
        inputHost:init("主机", "192.168.1.1", function(text) end, "192.168.1.1", "IP 或域名", 64)
        dialog:addView(inputHost)

        local inputUser = brls.InputCell.new()
        inputUser:init("用户名", "root", function(text) end, "root", "用户名", 32)
        dialog:addView(inputUser)

        local inputPort = brls.InputCell.new()
        inputPort:init("端口", "22", function(text) end, "22", "SSH 端口", 5)
        dialog:addView(inputPort)

        dialog:addButton("连接", function()
            local conn = {
                name = inputHost:getValue(),
                host = inputHost:getValue(),
                port = tonumber(inputPort:getValue()) or 22,
                user = inputUser:getValue(),
                password = "",
            }
            if conn.host and conn.host ~= "" and conn.user and conn.user ~= "" then
                self._connections = SavedConnections.upsert(conn)
                dialog:close()
                self:_doConnect(conn)
            end
        end)
    else
        -- InputCell 不可用，使用简单按钮
        dialog:addButton("示例: root@192.168.1.1", function()
            local conn = {
                name = "测试连接",
                host = "192.168.1.1",
                port = 22,
                user = "root",
                password = "",
            }
            dialog:close()
            self:_doConnect(conn)
        end)
    end

    dialog:addButton("取消", function() dialog:close() end)
    dialog:open()
end

-- ── 内部：执行连接 ────────────────────────────────────────────
function ConnectionView:_doConnect(conn)
    print("[SSH] Connecting to " .. conn.user .. "@" .. conn.host .. ":" .. (conn.port or 22))

    local params = {
        host        = conn.host,
        port        = conn.port or 22,
        user        = conn.user,
        password    = conn.password or "",
        privkey     = conn.privkey or "",
        timeout     = 10000,
        cols        = Platform.defaultCols,
        rows        = Platform.defaultRows,
    }

    -- 显示连接中对话框
    local connectingDlg = brls.Dialog.new("正在连接 " .. conn.host .. " ...")
    connectingDlg:addButton("取消", function()
        self._ssh:disconnect()
        connectingDlg:close()
    end)
    connectingDlg:open()

    -- 异步连接
    brls.Application.runAsync(100, function()
        local ok, err = self._ssh:connect(params)
        connectingDlg:close()
        if not ok then
            print("[SSH] Connection failed: " .. tostring(err))
            local errDlg = brls.Dialog.new("连接失败: " .. tostring(err))
            errDlg:addButton("确定", function() end)
            errDlg:open()
        end
    end)
end

-- ── 内部：切换到终端视图 ─────────────────────────────────────
function ConnectionView:_showTerminal()
    -- 使用 Dialog 显示终端（简化实现）
    local dialog = brls.Dialog.new("SSH 终端 (简化)\n" .. self._ssh:getInfo())

    -- 添加一些基本操作按钮
    dialog:addButton("发送命令 (示例: ls)", function()
        if self._ssh:isConnected() then
            self._ssh:send("ls\r")
        end
    end)

    dialog:addButton("发送 Ctrl+C", function()
        if self._ssh:isConnected() then
            self._ssh:send("\3")
        end
    end)

    dialog:addButton("断开连接", function()
        self._ssh:disconnect()
        dialog:close()
    end)

    dialog:open()
end

return ConnectionView
