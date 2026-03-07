-- =============================================================
-- connection_view.lua — SSH 连接管理 UI
-- 显示已保存的连接列表 + 新建/编辑连接表单
-- 连接成功后切换到 TerminalView
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
    self._activity     = nil   -- 由 main.lua 注入

    -- 配置 SSH 回调
    self._ssh.onData = function(data)
        self._terminal:feedData(data)
    end
    self._ssh.onConnect = function()
        self._terminal:setStatus(
            "已连接: " .. self._ssh:getInfo() ..
            "  FP: " .. self._ssh:getFingerprint():sub(1, 20) .. "…",
            80, 220, 80
        )
        -- 切换到终端界面
        self:_showTerminal()
    end
    self._ssh.onDisconnect = function()
        self._terminal:setStatus("已断开连接", 220, 80, 80)
        -- 延迟 2 秒后返回连接列表
        brls.Application.runAsync(2000, function()
            self:_showConnectionList()
        end)
    end
    self._ssh.onError = function(msg)
        -- 显示错误对话框
        brls.Application.blockInputs()
        local dialog = brls.Dialog.new("SSH 错误")
        dialog:addButton("确定", function()
            brls.Application.unblockInputs()
        end)
        dialog:open()
        brls.Logger.error("[SSH] " .. msg)
    end

    return self
end

-- ── 注入 Activity 引用 ───────────────────────────────────────
function ConnectionView:setActivity(activity)
    self._activity = activity
end

-- ── 显示连接列表页 ───────────────────────────────────────────
function ConnectionView:show()
    self._connections = SavedConnections.load()
    self:_showConnectionList()
end

-- ── 内部：显示连接列表 ───────────────────────────────────────
function ConnectionView:_showConnectionList()
    -- inflate 连接列表 XML
    local ok, view = pcall(function()
        return brls.View.inflate("@mod_ssh/xml/connect.xml")
    end)
    if not ok then
        brls.Logger.error("[SSH] Failed to inflate connect.xml: " .. tostring(view))
        return
    end

    -- 填充保存的连接（通过 RecyclerView 或 ScrollingFrame）
    local listContainer = view:getViewById("connection_list")
    if listContainer and #self._connections > 0 then
        for i, conn in ipairs(self._connections) do
            local item = self:_buildConnectionItem(conn, i)
            if item then listContainer:addView(item) end
        end
    end

    -- "新建连接"按钮
    local btnNew = view:getViewById("btn_new_connection")
    if btnNew then
        btnNew:registerClickAction(function()
            self:_showConnectForm(nil)
        end)
    end

    -- 在 Activity 中推入视图
    if self._activity then
        self._activity:setContentView(view)
    end
end

-- ── 内部：构建单个连接列表项 ─────────────────────────────────
function ConnectionView:_buildConnectionItem(conn, idx)
    -- 简单用 Label 展示，实际可换为 CellBase
    local ok, cell = pcall(function()
        return brls.View.inflate("@mod_ssh/xml/connect_item.xml")
    end)
    if not ok then return nil end

    -- 填充文字
    local lblName = cell:getViewById("lbl_conn_name")
    local lblHost = cell:getViewById("lbl_conn_host")
    if lblName then lblName:setFullText(conn.name or conn.host) end
    if lblHost then lblHost:setFullText(string.format("%s@%s:%d",
        conn.user or "?", conn.host or "?", conn.port or 22)) end

    -- 点击 → 连接
    cell:registerClickAction(function()
        self:_doConnect(conn)
    end)

    -- 长按 / Y键 → 编辑
    cell:registerAction("编辑", brls.ControllerButton.BUTTON_Y, function()
        self:_showConnectForm(conn, idx)
        return true
    end, false)

    -- X键 → 删除
    cell:registerAction("删除", brls.ControllerButton.BUTTON_X, function()
        local dialog = brls.Dialog.new("确认删除连接「" .. (conn.name or conn.host) .. "」？")
        dialog:addButton("删除", function()
            self._connections = SavedConnections.remove(idx)
            self:_showConnectionList()  -- 刷新列表
        end)
        dialog:addButton("取消", function() end)
        dialog:open()
        return true
    end, false)

    return cell
end

-- ── 内部：显示连接表单（新建/编辑）─────────────────────────
function ConnectionView:_showConnectForm(conn, editIdx)
    conn = conn or {}

    -- 弹出编辑 Dialog（也可以 inflate 独立页面）
    local dialog = brls.Dialog.new(editIdx and "编辑连接" or "新建 SSH 连接")

    -- 简化：使用多个 InputCell 构建表单
    -- 实际项目中可 inflate 完整 XML 表单
    local fields = {
        {id="name",       label="连接名称", value=conn.name      or ""},
        {id="host",       label="主机地址", value=conn.host      or ""},
        {id="port",       label="端口",     value=tostring(conn.port or 22)},
        {id="user",       label="用户名",   value=conn.user      or ""},
        {id="password",   label="密码",     value="" },  -- 密码不回显
        {id="privkey",    label="私钥路径", value=conn.privkey   or ""},
    }

    -- 临时存储输入值
    local values = {}
    for _, f in ipairs(fields) do
        values[f.id] = f.value
    end

    -- 添加确认按钮
    dialog:addButton("连接", function()
        local newConn = {
            name     = values.name ~= "" and values.name or values.host,
            host     = values.host,
            port     = tonumber(values.port) or 22,
            user     = values.user,
            password = values.password,
            privkey  = values.privkey,
        }
        local valid, errMsg = SavedConnections.validate(newConn)
        if not valid then
            brls.Logger.warning("[SSH] Invalid connection: " .. errMsg)
            -- 显示验证错误
            local errDlg = brls.Dialog.new("输入错误: " .. errMsg)
            errDlg:addButton("确定", function() end)
            errDlg:open()
            return
        end
        -- 保存并连接
        self._connections = SavedConnections.upsert(newConn)
        self:_doConnect(newConn)
    end)

    dialog:addButton("仅保存", function()
        local newConn = {
            name     = values.name ~= "" and values.name or values.host,
            host     = values.host,
            port     = tonumber(values.port) or 22,
            user     = values.user,
            password = values.password,
            privkey  = values.privkey,
        }
        local valid, errMsg = SavedConnections.validate(newConn)
        if valid then
            self._connections = SavedConnections.upsert(newConn)
            self:_showConnectionList()
        end
    end)

    dialog:addButton("取消", function() end)
    dialog:open()

    -- 注意：在真实实现中，需要为每个 fields 注册 Swkbd 输入
    -- 这里通过手柄 A 键触发系统键盘
    if Platform.isSwitch then
        -- Switch 上依次弹出各字段的软键盘
        -- 实际应该用 tabbing 机制，这里简化
    end
end

-- ── 内部：执行连接 ────────────────────────────────────────────
function ConnectionView:_doConnect(conn)
    -- 显示连接进度
    self._terminal:setStatus(
        string.format("正在连接 %s@%s:%d …", conn.user, conn.host, conn.port or 22),
        220, 220, 80
    )

    -- 在后台线程建立 SSH 连接（通过 brls 异步机制）
    -- 传递窗口尺寸
    local params = {
        host        = conn.host,
        port        = conn.port or 22,
        user        = conn.user,
        password    = conn.password,
        privkey     = conn.privkey,
        pubkey      = conn.pubkey,
        passphrase  = conn.passphrase,
        timeout     = 10000,
        cols        = Platform.defaultCols,
        rows        = Platform.defaultRows,
    }

    brls.Logger.info("[SSH] Connecting to {}@{}:{}", params.user, params.host, params.port)

    -- 在主线程调用（libssh2 在 Switch 上是同步阻塞，需在 async 中执行）
    brls.Application.runAsync(0, function()
        local ok, err = self._ssh:connect(params)
        if not ok then
            brls.Logger.error("[SSH] Connection failed: " .. tostring(err))
            self._terminal:setStatus("连接失败: " .. tostring(err), 220, 80, 80)
        end
    end)
end

-- ── 内部：切换到终端视图 ─────────────────────────────────────
function ConnectionView:_showTerminal()
    local ok, view = pcall(function()
        return brls.View.inflate("@mod_ssh/xml/terminal.xml")
    end)
    if not ok then
        brls.Logger.error("[SSH] Failed to inflate terminal.xml: " .. tostring(view))
        return
    end

    -- 找到终端绘制容器
    local termContainer = view:getViewById("terminal_canvas")
    if termContainer then
        self._terminal:bindView(termContainer)
    end

    -- 注册 LT/RT 翻页
    view:registerAction("向上翻页", brls.ControllerButton.BUTTON_LT, function()
        self._terminal:scrollUp(self._terminal._rows - 2)
        return true
    end, false)
    view:registerAction("向下翻页", brls.ControllerButton.BUTTON_RT, function()
        self._terminal:scrollDown(self._terminal._rows - 2)
        return true
    end, false)

    -- 返回连接列表
    view:registerAction("返回", brls.ControllerButton.BUTTON_START, function()
        self._ssh:disconnect()
        self:_showConnectionList()
        return true
    end, false)

    if self._activity then
        self._activity:setContentView(view)
    end
end

return ConnectionView
