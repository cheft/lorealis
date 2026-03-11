local SavedConnections = require("saved_connections")
local SSHHostParser = require("ssh_host_parser")
local SSHTerminalSession = require("ssh_terminal_session")

local SSHClientView = {}

local function notify(text)
    pcall(function()
        brls.Application.notify(text)
    end)
end

local Controller = {}
Controller.__index = Controller

function Controller.new(view)
    local self = setmetatable({}, Controller)
    self._view = view
    self._hostList = view:getView("ssh_host_list")
    self._emptyLabel = view:getView("ssh_empty_label")
    self._addButton = view:getView("ssh_add_host_button")
    self._rows = {}
    self._session = SSHTerminalSession.new()
    self:_bind()
    self:reload()
    return self
end

function Controller:_bind()
    if self._addButton then
        self._addButton:onClick(function()
            self:promptAddHost()
            return true
        end)
    end
end

function Controller:_clearRows()
    if not self._hostList then
        return
    end

    for _, row in ipairs(self._rows) do
        pcall(function()
            self._hostList:removeView(row)
        end)
    end
    self._rows = {}
end

function Controller:_renderRow(conn)
    local row = brls.Application.loadXMLRes("xml/views/ssh_host_row.xml")
    if not row then
        return nil
    end

    local connectButton = row:getView("ssh_row_connect_button")
    local deleteButton = row:getView("ssh_row_delete_button")
    if connectButton then
        connectButton:setText(conn.endpoint or conn.name or "")
    end

    if connectButton then
        connectButton:onClick(function()
            self:promptPasswordAndConnect(conn)
            return true
        end)
    end

    if deleteButton then
        deleteButton:onClick(function()
            self:confirmDelete(conn)
            return true
        end)
    end

    return row
end

function Controller:_setEmptyState(isEmpty)
    if self._emptyLabel then
        self._emptyLabel:setVisibility(isEmpty and brls.Visibility.VISIBLE or brls.Visibility.GONE)
    end
end

function Controller:reload()
    self:_clearRows()

    local list = SavedConnections.load()
    self:_setEmptyState(#list == 0)

    if not self._hostList then
        return
    end

    for _, conn in ipairs(list) do
        local row = self:_renderRow(conn)
        if row then
            self._hostList:addView(row)
            table.insert(self._rows, row)
        end
    end
end

function Controller:promptAddHost()
    local ok = brls.Application.openTextIME(function(text)
        self:addHostFromInput(text)
    end, "添加 SSH 主机", "使用 user@host:port，例如 jax@192.168.31.43:22", 128, "", 0)

    if not ok then
        notify("系统输入框不可用")
    end
end

function Controller:addHostFromInput(text)
    local conn, err = SSHHostParser.parse(text)
    if not conn then
        notify(err)
        return
    end

    local _, existed, saved = SavedConnections.upsert(conn)
    self:reload()

    if existed then
        notify("已更新主机: " .. conn.endpoint)
    else
        notify("已添加主机: " .. conn.endpoint)
    end

    if not saved then
        notify("主机列表保存失败，当前仅保留在本次运行中")
    end
end

function Controller:promptPasswordAndConnect(conn)
    local endpoint = conn.endpoint or conn.name or ""
    local ok = brls.Application.openTextIME(function(text)
        local password = text or ""
        if password == "" then
            notify("密码不能为空: " .. endpoint)
            return
        end
        self._session:open(conn, password)
    end, "SSH 密码", "输入 " .. endpoint .. " 的密码后立即连接", 128, "", 0)

    if not ok then
        notify("系统输入框不可用")
    end
end

function Controller:confirmDelete(conn)
    local endpoint = conn.endpoint or conn.name or ""
    local dialog = brls.Dialog.new("确认删除该主机？\n" .. endpoint)
    dialog:addButton("删除", function()
        local _, removed, saved = SavedConnections.removeByEndpoint(endpoint)
        if removed then
            brls.delay(1, function()
                self:reload()
                notify("已删除主机: " .. endpoint)
                if not saved then
                    notify("主机列表保存失败，删除仅影响本次运行")
                end
            end)
        else
            notify("未找到主机: " .. endpoint)
        end
        return true
    end)
    dialog:addButton("取消", function()
        return true
    end)
    dialog:open()
end

function SSHClientView.init(view)
    return Controller.new(view)
end

function SSHClientView.createView()
    local view = brls.Application.loadXMLRes("xml/tabs/ssh_client.xml")
    if view then
        SSHClientView.init(view)
    end
    return view
end

function SSHClientView.showActivity()
    local view = SSHClientView.createView()
    if not view then
        notify("SSH 页面加载失败")
        return
    end

    local frame = brls.AppletFrame.new()
    frame:setHeaderVisibility(brls.Visibility.GONE)
    frame:setFooterVisibility(brls.Visibility.GONE)
    frame:pushContentView(view)
    brls.Application.pushActivity(frame)
end

return SSHClientView
