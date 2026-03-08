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
        print("[SSH] onConnect callback started")
        self._terminal:setStatus("已连接: " .. self._ssh:getInfo(), 80, 220, 80)
        print("[SSH] setStatus done")
        -- 这里不再调用 _showTerminal，由 _doConnect 在关闭连接对话框后调用
    end
    self._ssh.onDisconnect = function()
        self._terminal:setStatus("已断开连接", 220, 80, 80)
        -- runAsync API 不存在，直接返回列表
        self:_showConnectionList()
    end
    self._ssh.onError = function(msg)
        self._errorDialog = brls.Dialog.new("SSH 错误: " .. msg)
        local dialog = self._errorDialog
        dialog:addButton("确定", function()
            self._errorDialog = nil
        end)
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
    -- 保存为成员变量防止被 Lua GC
    self._listDialog = brls.Dialog.new(title)
    local dialog = self._listDialog

    -- 为每个连接添加按钮
    for i, conn in ipairs(self._connections) do
        local btnText = (conn.name or conn.host) .. " (" .. conn.user .. "@" .. conn.host .. ")"
        dialog:addButton(btnText, function()
            dialog:close()
            self._listDialog = nil
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
    -- 保存为成员变量防止被 Lua GC
    self._formDialog = brls.Dialog.new("新建 SSH 连接")
    local dialog = self._formDialog

    -- 使用 InputCell 输入（如果可用）
    local ok, inputHost = pcall(function()
        return brls.InputCell.new()
    end)

    if ok and inputHost then
        inputHost:init("主机", "192.168.31.43", function(text) end, "192.168.31.43", "IP 或域名", 64)
        dialog:addView(inputHost)

        local inputUser = brls.InputCell.new()
        inputUser:init("用户名", "jax", function(text) end, "jax", "用户名", 32)
        dialog:addView(inputUser)

        local inputPort = brls.InputCell.new()
        inputPort:init("端口", "22", function(text) end, "22", "SSH 端口", 5)
        dialog:addView(inputPort)

        local inputPass = brls.InputCell.new()
        inputPass:init("密码", "jax2025", function(text) end, "", "密码（留空使用密钥）", 64)
        dialog:addView(inputPass)

        dialog:addButton("连接", function()
            local conn = {
                name = inputHost:getValue(),
                host = inputHost:getValue(),
                port = tonumber(inputPort:getValue()) or 22,
                user = inputUser:getValue(),
                password = inputPass:getValue(),
            }
            if conn.host and conn.host ~= "" and conn.user and conn.user ~= "" then
                self._connections = SavedConnections.upsert(conn)
                dialog:close()
                self._formDialog = nil
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

    -- 直接连接（不在异步中，因为 runAsync API 可能不存在）
    local ok, err = self._ssh:connect(params)
    pcall(function() connectingDlg:close() end)
    if not ok then
        print("[SSH] Connection failed: " .. tostring(err))
        local errDlg = brls.Dialog.new("连接失败: " .. tostring(err))
        errDlg:addButton("确定", function() return true end)
        errDlg:open()
    else
        -- 连接成功且对话框已关闭，显示终端
        self:_showTerminal()
    end
end

-- ── 内部：切换到终端视图 ─────────────────────────────────────
function ConnectionView:_showTerminal()
    print("[SSH] Showing Terminal")

    -- 创建全屏终端对话框
    self._terminalDialog = brls.Dialog.new("SSH 终端")
    local dialog = self._terminalDialog
    
    -- 创建一个 LuaImage 视图作为终端绘制载体
    local termViewObj = brls.LuaImage.new()
    -- 设置足够大的尺寸
    termViewObj:setWidth(1280)
    termViewObj:setHeight(720)
    -- termViewObj:setTranslationY(-20) -- 微调位置

    -- 将视图添加到对话框（Dialog 是一个 Box）
    dialog:addView(termViewObj)

    -- 绑定视图并初始化 (必须在 addView 之后，确保 termViewObj 有 parent)
    self._terminal:bindView(termViewObj)
    self._terminal:resize(1280, 720)

    -- 设置焦点，确保能接收键盘事件
    termViewObj:setFocusable(true)
    termViewObj:setFocus()

    -- 仅在 Switch 上显示“键盘”按钮，Desktop 使用物理键盘
    if Platform.isSwitch then
        dialog:addButton("键盘", function()
            self._terminal._keyboard:openSwkbd()
            return true
        end)
    end

    dialog:addButton("断开连接", function()
        self._ssh:disconnect()
        dialog:close()
        self._terminalDialog = nil
    end)

    dialog:open()
end

return ConnectionView
