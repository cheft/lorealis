-- =============================================================
-- main.lua — SSH 模块入口点
-- 由 Lorealis 模块加载器调用
-- 负责：初始化、创建 Activity、整合所有子模块
-- =============================================================

-- 模块根路径（供 require 使用）
-- 若 Lorealis 加载器已设置 package.path，此处不需要额外设置
-- 否则在此追加：
local _modPath = "mod/ssh/lua/"
if BRLS_RESOURCES and BRLS_RESOURCES == "romfs:/" then
    _modPath = "romfs:/mod/ssh/lua/"
end
package.path = package.path .. ";" .. _modPath .. "?.lua"

local Platform       = require("platform")
local ConnectionView = require("connection_view")
local _dbgOk, DebugLog = pcall(require, "debug_log")
if not _dbgOk then DebugLog = nil end

-- ── 全局状态 ───────────────────────────────────────────────
local _connView = nil
local _activity = nil

-- ── SSH 模块初始化 ─────────────────────────────────────────
local function init()
    print("[SSH Module] Initializing... (" .. Platform.info() .. ")")
    if DebugLog and DebugLog.append then
        pcall(function()
            DebugLog.append("[SSH Module] init, logPath=" .. tostring(DebugLog.path and DebugLog.path() or "unknown"))
        end)
    end

    local openTextIMEValue = brls and brls.Application and brls.Application.openTextIME
    local getControllerStateValue = brls and brls.Application and brls.Application.getControllerState
    local openTextIMELog = "[SSH Module] brls.Application.openTextIME type=" .. type(openTextIMEValue) .. ", value=" .. tostring(openTextIMEValue)
    local getControllerStateLog = "[SSH Module] brls.Application.getControllerState type=" .. type(getControllerStateValue) .. ", value=" .. tostring(getControllerStateValue)
    local debugPath = (DebugLog and DebugLog.path and DebugLog.path()) or "unknown"
    print(openTextIMELog)
    print(getControllerStateLog)
    print("[SSH Module] debug log path=" .. tostring(debugPath))
    if DebugLog and DebugLog.append then
        pcall(function()
            DebugLog.append(openTextIMELog)
            DebugLog.append(getControllerStateLog)
            DebugLog.append("[SSH Module] debug log path=" .. tostring(debugPath))
        end)
    end

    -- 验证 SSH 绑定是否可用
    if not brls.SSH then
        print("[SSH Module] brls.SSH bindings not found! Check lua_ssh.cpp registration.")
        local dlg = brls.Dialog.new("SSH 模块初始化失败\n\n缺少 brls.SSH 绑定层\n请检查编译配置")
        dlg:addButton("确定", function() end)
        dlg:open()
        return false
    end

    print("[SSH Module] libssh2 version: " .. brls.SSH.version())

    -- 创建连接管理视图
    _connView = ConnectionView.new()
    return true
end

-- ── 创建并显示 SSH Activity ────────────────────────────────
local function show()
    if not init() then return end

    -- 创建 TabFrame Activity（或直接推入当前 Activity 的内容）
    -- 根据实际 Borealis Lua API 调整
    local ok, activity = pcall(function()
        -- 方式 1：推入新的 AppletFrame Activity
        return brls.Application.pushActivity(
            brls.AppletFrame.new("SSH 客户端")
        )
    end)

    if ok and activity then
        _activity = activity
        _connView:setActivity(activity)

        -- 设置全局返回键处理
        activity:registerAction("返回", brls.ControllerButton.BUTTON_B, function()
            -- 如果 SSH 已连接，先提示确认
            if _connView._ssh and _connView._ssh:isConnected() then
                local dlg = brls.Dialog.new("SSH 会话仍在连接中，确认退出？")
                dlg:addButton("断开并退出", function()
                    _connView._ssh:disconnect()
                    brls.Application.popActivity()
                end)
                dlg:addButton("继续使用", function() end)
                dlg:open()
            else
                brls.Application.popActivity()
            end
            return true
        end, false)

    else
        -- 方式 2：在当前 Activity 内嵌显示（降级方案）
        print("[SSH Module] Could not push new activity, using inline mode.")
        -- getCurrentActivity API 不存在，直接尝试使用当前上下文
        -- 实际运行中 pushActivity 通常能成功，此分支很少进入
    end

    -- 显示连接列表
    _connView:show()

    print("[SSH Module] Ready.")
end

-- ── 模块清理（退出时调用）────────────────────────────────
local function cleanup()
    if _connView and _connView._ssh then
        _connView._ssh:disconnect()
    end
    _connView = nil
    print("[SSH Module] Cleaned up.")
end

-- ── 模块对外接口 ───────────────────────────────────────────
local M = {
    show    = show,
    cleanup = cleanup,
    -- 允许外部访问连接视图（调试用）
    getConnectionView = function() return _connView end,
}

-- ── 自动执行（若作为独立入口直接 doFile 时）───────────────
-- 判断是否为模块加载器调用还是直接执行
if not _SSH_MODULE_LOADED then
    _SSH_MODULE_LOADED = true
    -- 如果在主 Activity 初始化后调用，直接 show
    print("[SSH Module] Auto-starting...")
    show()
end

return M
