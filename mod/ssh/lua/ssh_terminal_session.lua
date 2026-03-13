local Platform = require("platform")
local SSHManager = require("ssh_manager")
local TerminalView = require("terminal_view")

local Session = {}
Session.__index = Session

local function notify(text)
    pcall(function()
        brls.Application.notify(text)
    end)
end

function Session.new()
    local self = setmetatable({}, Session)
    self._ssh = nil
    self._terminal = nil
    self._canvas = nil
    self._root = nil
    self._frame = nil
    self._activityOpen = false
    self._closing = false
    self._cleanupInProgress = false
    self._endpoint = nil
    self._lifecycleToken = 0
    return self
end

function Session:_nextLifecycleToken()
    self._lifecycleToken = (self._lifecycleToken or 0) + 1
    return self._lifecycleToken
end

function Session:_currentLifecycleToken()
    return self._lifecycleToken or 0
end

function Session:_clearSSHCallbacks()
    if not self._ssh then
        return
    end

    self._ssh.onData = nil
    self._ssh.onError = nil
    self._ssh.onDisconnect = nil
    self._ssh.onConnect = nil
end

function Session:_createCanvas()
    local canvas = brls.LuaImage.new()
    if canvas.setWidth then
        canvas:setWidth(brls.Application.windowWidth())
    end
    if canvas.setHeight then
        canvas:setHeight(brls.Application.windowHeight())
    end
    if canvas.setGrow then
        canvas:setGrow(1.0)
    end
    canvas:setFocusable(true)
    return canvas
end

function Session:_createRoot()
    local root = brls.Application.loadXMLRes("xml/views/ssh_terminal_screen.xml")
    return root
end

function Session:_teardownSession()
    local ssh = self._ssh
    self:_nextLifecycleToken()
    self:_clearSSHCallbacks()
    if ssh then
        pcall(function()
            ssh:disconnect()
        end)
    end
    self._ssh = nil
    self._terminal = nil
    self._canvas = nil
    self._root = nil
    self._frame = nil
    self._activityOpen = false
    self._closing = false
    self._cleanupInProgress = false
    self._endpoint = nil
end

function Session:_closeActivity()
    if self._cleanupInProgress then
        return
    end

    if not self._activityOpen then
        self:_teardownSession()
        return
    end

    self._cleanupInProgress = true
    self._activityOpen = false
    pcall(function()
        brls.Application.popActivity()
    end)
    self:_teardownSession()
end

function Session:_bindCallbacks()
    local token = self:_currentLifecycleToken()

    self._ssh.onData = function(data)
        if token ~= self:_currentLifecycleToken() then
            return
        end

        if self._terminal then
            self._terminal:feedData(data)
        end
    end

    self._ssh.onConnect = function()
        if token ~= self:_currentLifecycleToken() then
            return
        end

        if self._terminal then
            self._terminal:setStatus("Connected: " .. self._ssh:getInfo(), 80, 220, 80)
            self._terminal:_invalidate()
        end
        pcall(function()
            self._ssh:send("\r")
        end)
        brls.delay(30, function()
            if token ~= self:_currentLifecycleToken() then
                return
            end
            pcall(function()
                brls.Application.giveFocus(self._canvas)
            end)
        end)
        notify("SSH 已连接: " .. tostring(self._endpoint))
    end

    self._ssh.onError = function(message)
        if token ~= self:_currentLifecycleToken() then
            return
        end

        if self._terminal then
            self._terminal:setStatus("SSH Error: " .. tostring(message), 220, 120, 80)
        end
        notify("SSH 错误: " .. tostring(message))
    end

    self._ssh.onDisconnect = function()
        if token ~= self:_currentLifecycleToken() or self._cleanupInProgress then
            return
        end

        local shouldNotify = not self._closing
        self._closing = true
        if self._terminal then
            self._terminal:setStatus("Disconnected", 220, 80, 80)
        end
        if shouldNotify then
            notify("SSH 已断开: " .. tostring(self._endpoint))
        end
        brls.delay(50, function()
            if token ~= self:_currentLifecycleToken() then
                return
            end
            self:_closeActivity()
        end)
    end
end

function Session:open(conn, password)
    self:_teardownSession()
    self:_nextLifecycleToken()

    self._endpoint = conn.endpoint or string.format("%s@%s:%d", conn.user, conn.host, conn.port or 22)
    self._ssh = SSHManager.new()
    self._terminal = TerminalView.new(self._ssh)
    self._root = self:_createRoot()
    self._canvas = self:_createCanvas()
    self._frame = brls.AppletFrame.new()
    self._frame:setHeaderVisibility(brls.Visibility.GONE)
    self._frame:setFooterVisibility(brls.Visibility.GONE)
    if self._root and self._root.addView then
        if self._root.setGrow then
            self._root:setGrow(1.0)
        end
        self._root:addView(self._canvas)
        self._frame:pushContentView(self._root)
    else
        self._frame:pushContentView(self._canvas)
    end
    self._terminal:bindView(self._canvas)
    self._terminal:setOnCloseRequest(function()
        self._closing = true
        self:_closeActivity()
    end)
    self:_bindCallbacks()

    brls.Application.pushActivity(self._frame)
    self._activityOpen = true
    pcall(function()
        brls.Application.giveFocus(self._canvas)
    end)
    pcall(function()
        if self._terminal and self._terminal.ensureInputListeners then
            self._terminal:ensureInputListeners()
        end
    end)
    local token = self:_currentLifecycleToken()
    brls.delay(30, function()
        if token ~= self:_currentLifecycleToken() then
            return
        end
        pcall(function()
            brls.Application.giveFocus(self._canvas)
        end)
        pcall(function()
            if self._terminal and self._terminal.ensureInputListeners then
                self._terminal:ensureInputListeners()
            end
        end)
    end)

    self._terminal:resize(brls.Application.windowWidth(), brls.Application.windowHeight())
    self._terminal:setStatus("Connecting: " .. self._endpoint, 220, 180, 80)
    if Platform.isDesktop and self._terminal.setOverlayKeyboardVisible then
        self._terminal:setOverlayKeyboardVisible(true)
    end
    self._terminal:_invalidate()
    notify("正在连接 " .. self._endpoint)

    local ok, err = self._ssh:connect({
        host = conn.host,
        port = conn.port or 22,
        user = conn.user,
        password = password or "",
        timeout = 10000,
        cols = Platform.defaultCols,
        rows = Platform.defaultRows,
    })

    if not ok then
        if self._terminal then
            self._terminal:setStatus("Connection failed", 220, 80, 80)
        end
        notify("连接失败: " .. tostring(err))
        brls.delay(80, function()
            if token ~= self:_currentLifecycleToken() then
                return
            end
            self:_closeActivity()
        end)
        return false, err
    end

    return true
end

function Session:cleanup(skipPop)
    if skipPop then
        self:_teardownSession()
        return
    end

    self:_closeActivity()
end

return Session
