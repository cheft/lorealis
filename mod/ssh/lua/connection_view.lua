-- =============================================================
-- connection_view.lua — SSH 连接管理 UI（简化版本）
-- 仅使用已知可用的 Borealis Lua API
-- =============================================================

local Platform        = require("platform")
local SavedConnections= require("saved_connections")
local SSHManager      = require("ssh_manager")
local TerminalView    = require("terminal_view")
local _dbgOk, DebugLog = pcall(require, "debug_log")
if not _dbgOk then DebugLog = nil end

local TERMINAL_PAGE_WIDTH = 1280
local TERMINAL_PAGE_HEIGHT = 720

local function _setVisibilityIfExists(view, visibility)
    if view and view.setVisibility then
        view:setVisibility(visibility)
    end
end

local function _setTextIfExists(view, text)
    if view and view.setText then
        view:setText(text)
    end
end

local ConnectionView = {}
ConnectionView.__index = ConnectionView

local function _trace(msg)
    print(msg)
    if DebugLog and DebugLog.append then
        pcall(function()
            DebugLog.append(msg)
        end)
    end
end

-- ── 构造函数 ─────────────────────────────────────────────────
function ConnectionView.new()
    local self = setmetatable({}, ConnectionView)

    self._ssh          = SSHManager.new()
    self._terminal     = TerminalView.new(self._ssh)
    self._connections  = SavedConnections.load()
    self._activity     = nil
    self._terminalPage = nil
    self._terminalRoot = nil
    self._terminalCanvas = nil

    -- 配置 SSH 回调
    self._ssh.onData = function(data)
        self._terminal:feedData(data)
    end
    self._ssh.onConnect = function()
        print("[SSH] onConnect callback started")
        self._terminal:setStatus("已连接: " .. self._ssh:getInfo(), 80, 220, 80)
        self:_updateTerminalPageMeta()
        print("[SSH] setStatus done")
        -- 这里不再调用 _showTerminal，由 _doConnect 在关闭连接对话框后调用
    end
    self._ssh.onDisconnect = function()
        self._terminal:setStatus("已断开连接", 220, 80, 80)
        self:_popTerminalPageIfNeeded()
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

function ConnectionView:_updateTerminalPageMeta()
    if not self._terminalPage then return end

    local lblConnInfo = self._terminalPage:getView("lbl_conn_info")
    local lblSize = self._terminalPage:getView("lbl_terminal_size")
    local hintSwitch = self._terminalPage:getView("lbl_hints_switch")
    local hintDesktop = self._terminalPage:getView("lbl_hints_desktop")

    local infoText = "未连接"
    if self._ssh and self._ssh.getInfo then
        local ok, text = pcall(function()
            return self._ssh:getInfo()
        end)
        if ok and text and text ~= "" then
            infoText = text
        end
    end

    _setTextIfExists(lblConnInfo, infoText)
    _setTextIfExists(lblSize, string.format("%d×%d", Platform.defaultCols, Platform.defaultRows))

    if Platform.isSwitch then
        _setVisibilityIfExists(hintSwitch, brls.Visibility.VISIBLE)
        _setVisibilityIfExists(hintDesktop, brls.Visibility.GONE)
    else
        _setVisibilityIfExists(hintSwitch, brls.Visibility.GONE)
        _setVisibilityIfExists(hintDesktop, brls.Visibility.VISIBLE)
    end
end

function ConnectionView:_popTerminalPageIfNeeded()
    local dialog = self._terminalDialog or self._terminalRoot or self._terminalPage
    if dialog and dialog.close then
        pcall(function()
            dialog:close()
        end)
    end
    self._terminalDialog = nil
    self._terminalPage = nil
    self._terminalRoot = nil
    self._terminalCanvas = nil
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
    if DebugLog and DebugLog.clear then
        pcall(function()
            DebugLog.clear()
        end)
    end
    _trace("[SSH] Connecting to " .. conn.user .. "@" .. conn.host .. ":" .. (conn.port or 22))

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
        _trace("[SSH] Connection failed: " .. tostring(err))
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
    _trace("[SSH] Showing Terminal")

    self._terminalDialog = brls.Dialog.new("SSH 终端")
    local dialog = self._terminalDialog

    local terminalCanvas = brls.LuaImage.new()
    terminalCanvas:setWidth(TERMINAL_PAGE_WIDTH)
    terminalCanvas:setHeight(TERMINAL_PAGE_HEIGHT)
    terminalCanvas:setFocusable(true)

    dialog:addView(terminalCanvas)

    self._terminalPage = dialog
    self._terminalRoot = dialog
    self._terminalCanvas = terminalCanvas

    self._terminal:bindView(terminalCanvas)
    self._terminal:resize(TERMINAL_PAGE_WIDTH, TERMINAL_PAGE_HEIGHT)

    local terminalFrame = nil
    pcall(function()
        terminalFrame = dialog:getAppletFrame()
        if terminalFrame and terminalFrame.setFooterVisibility then
            terminalFrame:setFooterVisibility(brls.Visibility.VISIBLE)
        end
    end)

    local function triggerKeyboard()
        _trace("[SSH] Triggering keyboard via dialog button")
        self._terminal._keyboard:openSwkbd({
            header = "SSH Input",
            guide = "Press + to open keyboard, A to enter, B to delete",
        })
    end

    local function closeTerminal()
        _trace("[SSH] closeTerminal invoked, connected=" .. tostring(self._ssh:isConnected()))
        if self._ssh:isConnected() then
            self._ssh:disconnect()
        else
            self:_popTerminalPageIfNeeded()
        end
    end

    self._terminal._onCloseRequest = closeTerminal

    if not Platform.isSwitch then
        dialog:addButton("Disconnect", function()
            closeTerminal()
            return true
        end)
    end

    dialog:open()
    _trace("[SSH] Terminal dialog opened")

    -- Switch: bind actions on the Dialog AppletFrame itself so they win over Dialog defaults
    if Platform.isSwitch and terminalFrame then
        local ok, err = pcall(function()
            terminalFrame:registerAction("Enter", brls.ControllerButton.BUTTON_A, function()
                _trace("[SSH] Frame A pressed")
                self._terminal:_sendInput(Platform.keyMap.ENTER)
                return true
            end)
            terminalFrame:registerAction("Delete", brls.ControllerButton.BUTTON_B, function()
                _trace("[SSH] Frame B pressed")
                self._terminal:_sendInput(Platform.keyMap.BS)
                return true
            end)
            terminalFrame:registerAction("Ctrl+C", brls.ControllerButton.BUTTON_X, function()
                self._terminal:_sendInput(Platform.keyMap.CTRL_C)
                return true
            end)
            terminalFrame:registerAction("EOF", brls.ControllerButton.BUTTON_Y, function()
                self._terminal:_sendInput(Platform.keyMap.CTRL_D)
                return true
            end)
            terminalFrame:registerAction("Tab", brls.ControllerButton.BUTTON_LB, function()
                self._terminal:_sendInput(Platform.keyMap.TAB)
                return true
            end)
            terminalFrame:registerAction("Reconnect", brls.ControllerButton.BUTTON_RB, function()
                if self._ssh:isConnected() then
                    self._ssh:disconnect()
                else
                    self._ssh:reconnect()
                end
                return true
            end)
            terminalFrame:registerAction("Keyboard", brls.ControllerButton.BUTTON_START, function()
                _trace("[SSH] Frame START(+) pressed")
                triggerKeyboard()
                return true
            end)
            terminalFrame:registerAction("Close", brls.ControllerButton.BUTTON_BACK, function()
                _trace("[SSH] Frame BACK(-) pressed")
                closeTerminal()
                return true
            end)
        end)
        if not ok then
            _trace("[SSH] Frame action bind failed: " .. tostring(err))
        end
    end

    pcall(function()
        terminalCanvas:setFocus()
    end)
    -- 对话框打开后会重置一次焦点，延迟再给一次
    brls.delay(50, function()
        pcall(function()
            terminalCanvas:setFocus()
        end)
    end)
end

return ConnectionView
