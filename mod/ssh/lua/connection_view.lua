local Platform = require("platform")
local SavedConnections = require("saved_connections")
local SSHManager = require("ssh_manager")
local TerminalView = require("terminal_view")

local okDebugLog, DebugLog = pcall(require, "debug_log")
if not okDebugLog then DebugLog = nil end

local TERMINAL_PAGE_WIDTH = 1280
local TERMINAL_PAGE_HEIGHT = 720

local function trace(message)
    print(message)
    if DebugLog and DebugLog.append then
        pcall(function()
            DebugLog.append(message)
        end)
    end
end

local function safeClose(dialog)
    if dialog and dialog.close then
        pcall(function()
            dialog:close()
        end)
    end
end

local ConnectionView = {}
ConnectionView.__index = ConnectionView

function ConnectionView.new()
    local self = setmetatable({}, ConnectionView)

    self._activity = nil
    self._connections = SavedConnections.load()

    self._listDialog = nil
    self._formDialog = nil
    self._errorDialog = nil
    self._connectingDialog = nil
    self._terminalDialog = nil
    self._terminalPage = nil
    self._terminalRoot = nil
    self._terminalCanvas = nil

    self._closingTerminal = false

    self:_recreateSessionContext()
    return self
end

function ConnectionView:_bindSSHCallbacks()
    self._ssh.onData = function(data)
        if self._terminal then
            self._terminal:feedData(data)
        end
    end

    self._ssh.onConnect = function()
        trace("[SSH] onConnect callback started")
        if self._terminal then
            self._terminal:setStatus("Connected: " .. self._ssh:getInfo(), 80, 220, 80)
        end
        self:_updateTerminalPageMeta()
    end

    self._ssh.onDisconnect = function()
        trace("[SSH] onDisconnect callback started")
        if self._terminal then
            self._terminal:setStatus("Disconnected", 220, 80, 80)
        end

        self:_popTerminalPageIfNeeded()
        self:_closeTransientDialogs()
        self:_recreateSessionContext()
        self._closingTerminal = false

        brls.delay(80, function()
            self:_showConnectionList()
        end)
    end

    self._ssh.onError = function(message)
        safeClose(self._errorDialog)
        self._errorDialog = brls.Dialog.new("SSH Error: " .. tostring(message))
        local dialog = self._errorDialog
        dialog:addButton("OK", function()
            self._errorDialog = nil
            return true
        end)
        dialog:open()
        trace("[SSH] " .. tostring(message))
    end
end

function ConnectionView:_recreateSessionContext()
    self._ssh = SSHManager.new()
    self._terminal = TerminalView.new(self._ssh)
    self:_bindSSHCallbacks()
end

function ConnectionView:_closeTransientDialogs()
    safeClose(self._listDialog)
    safeClose(self._formDialog)
    safeClose(self._errorDialog)
    safeClose(self._connectingDialog)
    self._listDialog = nil
    self._formDialog = nil
    self._errorDialog = nil
    self._connectingDialog = nil
end

function ConnectionView:_updateTerminalPageMeta()
end

function ConnectionView:_popTerminalPageIfNeeded()
    safeClose(self._terminalDialog or self._terminalRoot or self._terminalPage)
    self._terminalDialog = nil
    self._terminalPage = nil
    self._terminalRoot = nil
    self._terminalCanvas = nil
end

function ConnectionView:setActivity(activity)
    self._activity = activity
end

function ConnectionView:show()
    self._connections = SavedConnections.load()
    self:_showConnectionList()
end

function ConnectionView:_showConnectionList()
    self._connections = SavedConnections.load()
    self:_closeTransientDialogs()

    local title = "SSH Client"
    if #self._connections == 0 then
        title = "SSH Client - No Connections"
    else
        title = string.format("SSH Client - %d Connection(s)", #self._connections)
    end

    self._listDialog = brls.Dialog.new(title)
    local dialog = self._listDialog

    for _, conn in ipairs(self._connections) do
        local label = string.format("%s (%s@%s)", conn.name or conn.host, conn.user, conn.host)
        dialog:addButton(label, function()
            safeClose(dialog)
            self._listDialog = nil
            self:_doConnect(conn)
            return true
        end)
    end

    dialog:addButton("+ New Connection", function()
        safeClose(dialog)
        self._listDialog = nil
        self:_showConnectForm()
        return true
    end)

    dialog:open()
end

function ConnectionView:_showConnectForm()
    self._formDialog = brls.Dialog.new("New SSH Connection")
    local dialog = self._formDialog

    local okInput, inputHost = pcall(function()
        return brls.InputCell.new()
    end)

    if okInput and inputHost then
        inputHost:init("Host", "192.168.31.43", function() end, "192.168.31.43", "IP or hostname", 64)
        dialog:addView(inputHost)

        local inputUser = brls.InputCell.new()
        inputUser:init("User", "jax", function() end, "root", "Username", 32)
        dialog:addView(inputUser)

        local inputPort = brls.InputCell.new()
        inputPort:init("Port", "22", function() end, "22", "SSH port", 5)
        dialog:addView(inputPort)

        local inputPass = brls.InputCell.new()
        inputPass:init("Password", "jax2025", function() end, "", "Password", 64)
        dialog:addView(inputPass)

        dialog:addButton("Connect", function()
            local conn = {
                name = inputHost:getValue(),
                host = inputHost:getValue(),
                port = tonumber(inputPort:getValue()) or 22,
                user = inputUser:getValue(),
                password = inputPass:getValue(),
            }

            if conn.host and conn.host ~= "" and conn.user and conn.user ~= "" then
                self._connections = SavedConnections.upsert(conn)
                safeClose(dialog)
                self._formDialog = nil
                self:_doConnect(conn)
            end
            return true
        end)
    else
        dialog:addButton("Example: root@192.168.1.1", function()
            local conn = {
                name = "Test Connection",
                host = "192.168.1.1",
                port = 22,
                user = "root",
                password = "",
            }
            safeClose(dialog)
            self._formDialog = nil
            self:_doConnect(conn)
            return true
        end)
    end

    dialog:addButton("Cancel", function()
        safeClose(dialog)
        self._formDialog = nil
        self:_showConnectionList()
        return true
    end)

    dialog:open()
end

function ConnectionView:_doConnect(conn)
    if DebugLog and DebugLog.clear then
        pcall(function()
            DebugLog.clear()
        end)
    end

    self:_closeTransientDialogs()
    self:_popTerminalPageIfNeeded()
    self:_recreateSessionContext()

    trace(string.format("[SSH] Connecting to %s@%s:%d", conn.user, conn.host, conn.port or 22))

    local params = {
        host = conn.host,
        port = conn.port or 22,
        user = conn.user,
        password = conn.password or "",
        privkey = conn.privkey or "",
        timeout = 10000,
        cols = Platform.defaultCols,
        rows = Platform.defaultRows,
    }

    self._connectingDialog = brls.Dialog.new("Connecting " .. conn.host .. " ...")
    local connectingDialog = self._connectingDialog
    connectingDialog:addButton("Cancel", function()
        pcall(function()
            self._ssh:disconnect()
        end)
        safeClose(connectingDialog)
        self._connectingDialog = nil
        self:_recreateSessionContext()
        self:_showConnectionList()
        return true
    end)
    connectingDialog:open()

    local ok, err = self._ssh:connect(params)
    safeClose(connectingDialog)
    self._connectingDialog = nil

    if not ok then
        trace("[SSH] Connection failed: " .. tostring(err))
        safeClose(self._errorDialog)
        self._errorDialog = brls.Dialog.new("Connection failed: " .. tostring(err))
        self._errorDialog:addButton("OK", function()
            self._errorDialog = nil
            self:_showConnectionList()
            return true
        end)
        self._errorDialog:open()
        return
    end

    self:_showTerminal()
end

function ConnectionView:_showTerminal()
    trace("[SSH] Showing terminal")

    self:_closeTransientDialogs()
    self:_popTerminalPageIfNeeded()

    self._terminalDialog = brls.Dialog.new("SSH Terminal")
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
    self._terminal:setStatus("Connected: " .. self._ssh:getInfo(), 80, 220, 80)

    pcall(function()
        local frame = dialog:getAppletFrame()
        if frame and frame.setFooterVisibility then
            frame:setFooterVisibility(brls.Visibility.VISIBLE)
        end
    end)

    local function closeTerminal()
        if self._closingTerminal then
            return true
        end

        self._closingTerminal = true
        trace("[SSH] closeTerminal invoked")

        self:_popTerminalPageIfNeeded()
        pcall(function()
            self._ssh:disconnect()
        end)
        self:_recreateSessionContext()

        brls.delay(80, function()
            self._closingTerminal = false
            self:_showConnectionList()
        end)

        return true
    end

    self._terminal._onCloseRequest = closeTerminal

    if not Platform.isSwitch then
        dialog:addButton("Disconnect", closeTerminal)
    end

    dialog:open()

    pcall(function()
        terminalCanvas:setFocus()
    end)

    brls.delay(50, function()
        pcall(function()
            terminalCanvas:setFocus()
        end)
    end)
end

return ConnectionView
