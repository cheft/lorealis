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
    self._frame = nil
    self._activityOpen = false
    self._closing = false
    self._endpoint = nil
    return self
end

function Session:_createCanvas()
    local canvas = brls.LuaImage.new()
    canvas:setWidth(brls.Application.windowWidth())
    canvas:setHeight(brls.Application.windowHeight())
    canvas:setFocusable(true)
    return canvas
end

function Session:_teardownSession()
    if self._ssh then
        pcall(function()
            self._ssh:disconnect()
        end)
    end
    self._ssh = nil
    self._terminal = nil
    self._canvas = nil
    self._frame = nil
    self._activityOpen = false
    self._closing = false
    self._endpoint = nil
end

function Session:_closeActivity()
    if not self._activityOpen then
        self:_teardownSession()
        return
    end

    self._activityOpen = false
    pcall(function()
        brls.Application.popActivity()
    end)
    self:_teardownSession()
end

function Session:_bindCallbacks()
    self._ssh.onData = function(data)
        if self._terminal then
            self._terminal:feedData(data)
        end
    end

    self._ssh.onConnect = function()
        if self._terminal then
            self._terminal:setStatus("Connected: " .. self._ssh:getInfo(), 80, 220, 80)
        end
        notify("SSH 已连接: " .. tostring(self._endpoint))
    end

    self._ssh.onError = function(message)
        if self._terminal then
            self._terminal:setStatus("SSH Error: " .. tostring(message), 220, 120, 80)
        end
        notify("SSH 错误: " .. tostring(message))
    end

    self._ssh.onDisconnect = function()
        local shouldNotify = not self._closing
        self._closing = true
        if self._terminal then
            self._terminal:setStatus("Disconnected", 220, 80, 80)
        end
        if shouldNotify then
            notify("SSH 已断开: " .. tostring(self._endpoint))
        end
        brls.delay(50, function()
            self:_closeActivity()
        end)
    end
end

function Session:open(conn, password)
    self:_teardownSession()

    self._endpoint = conn.endpoint or string.format("%s@%s:%d", conn.user, conn.host, conn.port or 22)
    self._ssh = SSHManager.new()
    self._terminal = TerminalView.new(self._ssh)
    self._canvas = self:_createCanvas()
    self._frame = brls.AppletFrame.new()
    self._frame:setHeaderVisibility(brls.Visibility.GONE)
    self._frame:setFooterVisibility(brls.Visibility.GONE)
    self._frame:pushContentView(self._canvas)
    self._terminal:bindView(self._canvas)
    self._terminal:setOnCloseRequest(function()
        self._closing = true
        if self._ssh and self._ssh:isConnected() then
            self._ssh:disconnect()
        else
            self:_closeActivity()
        end
    end)
    self:_bindCallbacks()

    brls.Application.pushActivity(self._frame)
    self._activityOpen = true
    pcall(function()
        brls.Application.giveFocus(self._canvas)
    end)

    self._terminal:resize(brls.Application.windowWidth(), brls.Application.windowHeight())
    self._terminal:setStatus("Connecting: " .. self._endpoint, 220, 180, 80)
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
            self:_closeActivity()
        end)
        return false, err
    end

    return true
end

return Session
