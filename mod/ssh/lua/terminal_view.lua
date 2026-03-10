-- =============================================================
-- terminal_view.lua — 终端视图渲染层
-- 基于 brls.CustomView（自定义 NanoVG 绘制）
-- 将 TerminalBuffer 内容渲染为彩色终端输出
-- 处理手柄/键盘输入，与 SSHManager 联动
-- =============================================================

local Platform      = require("platform")
local AnsiParser    = require("ansi_parser")
local TerminalBuffer= require("terminal_buffer")
local SSHManager    = require("ssh_manager")
local Keyboard      = require("keyboard")
local _dbgOk, DebugLog = pcall(require, "debug_log")
if not _dbgOk then DebugLog = nil end

local function _trace(msg)
    print(msg)
    if DebugLog and DebugLog.append then
        pcall(function()
            DebugLog.append(msg)
        end)
    end
end

-- ── NanoVG Aliases ──────────────────────────────────────────
local nvgBeginPath    = brls.nvgBeginPath
local nvgFill         = brls.nvgFill
local nvgRect         = brls.nvgRect
local nvgFillColor    = brls.nvgFillColor
local nvgFontSize     = brls.nvgFontSize
local nvgFontFace     = brls.nvgFontFace
local nvgTextAlign    = brls.nvgTextAlign
local nvgRoundedRect  = brls.nvgRoundedRect
local nvgMoveTo       = brls.nvgMoveTo
local nvgLineTo       = brls.nvgLineTo
local nvgStrokeColor  = brls.nvgStrokeColor
local nvgStrokeWidth  = brls.nvgStrokeWidth
local nvgStroke       = brls.nvgStroke
local nvgFontBlur     = brls.nvgFontBlur
local nvgText         = brls.nvgText
local nvgRGBA         = brls.nvgRGBA

-- Alignment Constants
local NVG_ALIGN_LEFT   = brls.NVG_ALIGN_LEFT
local NVG_ALIGN_CENTER = brls.NVG_ALIGN_CENTER
local NVG_ALIGN_RIGHT  = brls.NVG_ALIGN_RIGHT
local NVG_ALIGN_TOP    = brls.NVG_ALIGN_TOP
local NVG_ALIGN_MIDDLE = brls.NVG_ALIGN_MIDDLE
local NVG_ALIGN_BOTTOM = brls.NVG_ALIGN_BOTTOM

local TerminalView = {}
TerminalView.__index = TerminalView

-- ── 字体/渲染参数 ─────────────────────────────────────────────
local FONT_SIZE   = 16        -- 字体大小
local LINE_HEIGHT = 18       -- 行高
local CHAR_WIDTH  = 9      -- 字符宽度（Consolas 18px 约 10.5）
local WIDE_CHAR_WIDTH = 10  -- 中文字符宽度（调整为比 2*CHAR_WIDTH 小一点，解决字间距过大问题）
local PADDING_X   = 10
local PADDING_Y   = 10
local CURSOR_BLINK_RATE = 0.5 -- 秒
local CURSOR_BLINK_INTERVAL = 500  -- ms

local SWITCH_HINT_TEXT = "DPad Arrows  A Enter  B BS  L Tab  + IME  R3 Keyboard  - Close"
local DESKTOP_HINT_TEXT = "Direct keyboard input | Ctrl+K keyboard | Ctrl+C interrupt | PageUp/Down history"

local OVERLAY_HINT_TEXT = "Touch/A Type  B BS  X Shift  Y Space  L Tab  Enter Submit  + IME  R3 Hide"
local DPAD_REPEAT_DELAY_MS = 550
local DPAD_REPEAT_INTERVAL_MS = 180
local OVERLAY_RUMBLE_LOW = 2600
local OVERLAY_RUMBLE_HIGH = 4800
local OVERLAY_RUMBLE_INTERVAL_MS = 45
local OVERLAY_RUMBLE_PULSE_MS = 28

local function _key(label, opts)
    opts = opts or {}
    opts.label = label
    opts.width = opts.width or 1
    return opts
end

local OVERLAY_ROW_COLORS = {
    { 114, 74, 222 },
    { 64, 124, 255 },
    { 34, 182, 165 },
    { 72, 166, 88 },
    { 214, 146, 52 },
}

local function _withAlpha(color, alpha)
    return nvgRGBA(color[1], color[2], color[3], alpha or 255)
end

local function _overlayKeyPalette(key, rowIndex, selected, active)
    local base = OVERLAY_ROW_COLORS[rowIndex] or OVERLAY_ROW_COLORS[#OVERLAY_ROW_COLORS]

    if key.action == "enter" then
        base = { 255, 120, 64 }
    elseif key.action == "backspace" then
        base = { 232, 88, 102 }
    elseif key.action == "shift" or key.action == "caps" then
        base = { 160, 92, 235 }
    elseif key.action == "ctrl" or key.action == "alt" then
        base = { 76, 164, 255 }
    elseif key.action == "tab" then
        base = { 72, 192, 150 }
    elseif key.action == "space" then
        base = { 72, 156, 224 }
    elseif key.action == "send" then
        base = { 92, 104, 122 }
    elseif key.action == "text" then
        base = { 230, 134, 74 }
    end

    local fill = { base[1], base[2], base[3] }
    local border = { math.min(255, base[1] + 26), math.min(255, base[2] + 26), math.min(255, base[3] + 26) }
    local top = { math.min(255, base[1] + 46), math.min(255, base[2] + 46), math.min(255, base[3] + 46) }

    if active then
        fill = { math.min(255, fill[1] + 34), math.min(255, fill[2] + 34), math.min(255, fill[3] + 34) }
        border = { 255, 255, 255 }
    elseif selected then
        fill = { math.min(255, fill[1] + 22), math.min(255, fill[2] + 22), math.min(255, fill[3] + 22) }
        border = { 255, 244, 190 }
    end

    return {
        fill = _withAlpha(fill, 232),
        border = _withAlpha(border, 248),
        top = _withAlpha(top, 208),
        text = nvgRGBA(255, 255, 255, 255),
    }
end

local function _overlayChipPalette(index, item)
    local palettes = {
        { 66, 132, 245 },
        { 46, 184, 146 },
        { 214, 132, 70 },
        { 166, 96, 232 },
        { 224, 92, 122 },
    }

    local base = palettes[((index - 1) % #palettes) + 1]
    if item and item.mode == "replace" then
        base = { math.min(255, base[1] + 16), math.min(255, base[2] + 16), math.min(255, base[3] + 16) }
    end

    return {
        fill = _withAlpha(base, 224),
        border = _withAlpha({ math.min(255, base[1] + 28), math.min(255, base[2] + 28), math.min(255, base[3] + 28) }, 244),
        text = nvgRGBA(255, 255, 255, 255),
    }
end

local OVERLAY_QUICK_COMMANDS = { "ls", "cd", "pwd", "clear" }
local OVERLAY_QUICK_SYMBOLS = { "~", "$", "*", "|", "&&" }
local OVERLAY_COMMON_COMMANDS = {
    "ls", "cd", "pwd", "clear", "cat", "echo", "mkdir", "rm", "cp", "mv",
    "touch", "grep", "find", "git", "top", "htop", "vim", "nano", "ssh", "scp",
}

local OVERLAY_LAYOUT = {
    {
        _key("Esc", { action = "send", value = Platform.keyMap.ESC, width = 1.25 }),
        _key("1", { action = "char", base = "1", shift = "!" }),
        _key("2", { action = "char", base = "2", shift = "@" }),
        _key("3", { action = "char", base = "3", shift = "#" }),
        _key("4", { action = "char", base = "4", shift = "$" }),
        _key("5", { action = "char", base = "5", shift = "%" }),
        _key("6", { action = "char", base = "6", shift = "^" }),
        _key("7", { action = "char", base = "7", shift = "&" }),
        _key("8", { action = "char", base = "8", shift = "*" }),
        _key("9", { action = "char", base = "9", shift = "(" }),
        _key("0", { action = "char", base = "0", shift = ")" }),
        _key("-", { action = "char", base = "-", shift = "_" }),
        _key("=", { action = "char", base = "=", shift = "+" }),
        _key("BS", { action = "backspace", width = 1.75 }),
    },
    {
        _key("Tab", { action = "tab", width = 1.6 }),
        _key("q", { action = "char", base = "q", letter = true }),
        _key("w", { action = "char", base = "w", letter = true }),
        _key("e", { action = "char", base = "e", letter = true }),
        _key("r", { action = "char", base = "r", letter = true }),
        _key("t", { action = "char", base = "t", letter = true }),
        _key("y", { action = "char", base = "y", letter = true }),
        _key("u", { action = "char", base = "u", letter = true }),
        _key("i", { action = "char", base = "i", letter = true }),
        _key("o", { action = "char", base = "o", letter = true }),
        _key("p", { action = "char", base = "p", letter = true }),
        _key("[", { action = "char", base = "[", shift = "{" }),
        _key("]", { action = "char", base = "]", shift = "}" }),
        _key("\\", { action = "char", base = "\\", shift = "|", width = 1.35 }),
    },
    {
        _key("Caps", { action = "caps", width = 1.95 }),
        _key("a", { action = "char", base = "a", letter = true }),
        _key("s", { action = "char", base = "s", letter = true }),
        _key("d", { action = "char", base = "d", letter = true }),
        _key("f", { action = "char", base = "f", letter = true }),
        _key("g", { action = "char", base = "g", letter = true }),
        _key("h", { action = "char", base = "h", letter = true }),
        _key("j", { action = "char", base = "j", letter = true }),
        _key("k", { action = "char", base = "k", letter = true }),
        _key("l", { action = "char", base = "l", letter = true }),
        _key(";", { action = "char", base = ";", shift = ":" }),
        _key("'", { action = "char", base = "'", shift = '"' }),
        _key("Enter", { action = "enter", width = 2.15 }),
    },
    {
        _key("Shift", { action = "shift", width = 2.3 }),
        _key("z", { action = "char", base = "z", letter = true }),
        _key("x", { action = "char", base = "x", letter = true }),
        _key("c", { action = "char", base = "c", letter = true }),
        _key("v", { action = "char", base = "v", letter = true }),
        _key("b", { action = "char", base = "b", letter = true }),
        _key("n", { action = "char", base = "n", letter = true }),
        _key("m", { action = "char", base = "m", letter = true }),
        _key(",", { action = "char", base = ",", shift = "<" }),
        _key(".", { action = "char", base = ".", shift = ">" }),
        _key("/", { action = "char", base = "/", shift = "?" }),
        _key("`", { action = "char", base = "`", shift = "~", width = 1.35 }),
    },
    {
        _key("Ctrl", { action = "ctrl", width = 1.4 }),
        _key("Alt", { action = "alt", width = 1.4 }),
        _key("Space", { action = "space", width = 4.9 }),
        _key("←", { action = "send", value = Platform.keyMap.LEFT, width = 1.2 }),
        _key("↓", { action = "send", value = Platform.keyMap.DOWN, width = 1.2 }),
        _key("↑", { action = "send", value = Platform.keyMap.UP, width = 1.2 }),
        _key("→", { action = "send", value = Platform.keyMap.RIGHT, width = 1.2 }),
        _key("Tab", { action = "tab", width = 1.2 }),
        _key("&&", { action = "text", value = "&&", width = 1.3 }),
        _key("|", { action = "text", value = "|", width = 1.0 }),
    },
}

-- 默认背景色（几乎纯黑）
local BG_R, BG_G, BG_B = 12, 12, 12

-- ── 构造函数 ─────────────────────────────────────────────────
---@param sshManager SSHManager
function TerminalView.new(sshManager)
    local self = setmetatable({}, TerminalView)

    self._ssh      = sshManager
    self._parser   = AnsiParser.new()
    self._cols     = Platform.defaultCols
    self._rows     = Platform.defaultRows
    self._buf      = TerminalBuffer.new(self._cols, self._rows)
    self._keyboard = Keyboard.new(function(data) self:_sendInput(data) end)

    -- 视图对象（由 brls XML inflate 后注入）
    self._view     = nil

    -- 光标闪烁状态
    self._cursorVisible  = true
    self._blinkTimer     = 0
    self._blinkOn        = true

    -- 滚动偏移（历史缓冲区查看，0 = 底部最新）
    self._scrollOffset   = 0
    self._maxScroll      = 0

    -- 状态栏信息
    self._statusText     = "未连接"
    self._statusColor    = {r=150, g=150, b=150}

    -- 选择区域 {startRow, startCol, endRow, endCol} (绝对行号，包含历史)
    self._selection      = nil
    self._selecting      = false

    -- 日志（用于调试输出）
    self._log            = {}
    self._logEnabled     = false
    self._lastPolledButtons = {}
    self._onCloseRequest = nil
    self._debugButtonsText = "DBG init"
    self._debugPollText = ""
    self._debugFrameCount = 0
    self._overlayKeyboardVisible = false
    self._overlayBuffer = ""
    self._overlayShift = false
    self._overlayCaps = false
    self._overlayCtrl = false
    self._overlayAlt = false
    self._overlayTouchTargets = {}
    self._overlayPanelRect = nil
    self._overlaySelectedKey = OVERLAY_LAYOUT[2][2]
    self._overlayRecentCommands = {}
    self._drawX = 0
    self._drawY = 0
    self._drawW = 0
    self._drawH = 0
    self._buttonRepeatState = {}
    self._touchState = { pressed = false, x = 0, y = 0, id = -1 }
    self._lastOverlayRumbleAt = 0
    self._overlayRumbleSeq = 0
    self._overlayRumbleCooling = false

    return self
end

-- ── 绑定 brls View 对象 ──────────────────────────────────────
-- 由 connection_view.lua 在创建视图后调用
function TerminalView:bindView(view)
    self._view = view
    if view then
        -- 注册自定义绘制回调
        view:setDrawCallback(function(vg, x, y, w, h, style, ctx)
            self:_draw(vg, x, y, w, h)
        end)
        
        -- 确保视图可以获取焦点
        if view.setFocusable then
            view:setFocusable(true)
        end
        
        -- Switch 上统一使用原始轮询，避免和 Dialog/AppletFrame action 链重复触发。
        if not Platform.isSwitch then
            view:registerAction("Enter", brls.ControllerButton.BUTTON_A, function()
                self:_sendInput(Platform.keyMap.ENTER)
                return true
            end, false)
            view:registerAction("Delete", brls.ControllerButton.BUTTON_B, function()
                self:_sendInput(Platform.keyMap.BS)
                return true
            end, false)
            view:registerAction("Ctrl+C", brls.ControllerButton.BUTTON_X, function()
                self:_sendInput(Platform.keyMap.CTRL_C)
                return true
            end, false)
            view:registerAction("EOF", brls.ControllerButton.BUTTON_Y, function()
                self:_sendInput(Platform.keyMap.CTRL_D)
                return true
            end, false)
            view:registerAction("Tab", brls.ControllerButton.BUTTON_LB, function()
                self:_sendInput(Platform.keyMap.TAB)
                return true
            end, false)
            view:registerAction("System IME", brls.ControllerButton.BUTTON_START, function()
                self:_openSystemIme()
                return true
            end, false)
            view:registerAction("Close", brls.ControllerButton.BUTTON_BACK, function()
                if self._ssh:isConnected() then
                    self._ssh:disconnect()
                end
                return true
            end, false)
        end
        -- 在全局表中注册此视图，方便键盘事件路由
        _G.__SSH_TERMINALS = _G.__SSH_TERMINALS or {}
        local addr = tostring(view:get_address())
        _G.__SSH_TERMINALS[addr] = self
        print("[TerminalView] Registered mapping for address: " .. addr)

        -- 同时注册可能的所有上级视图，直到顶层（捕获不同层次的焦点）
        local curr = view:getParent()
        while curr do
            local paddr = tostring(curr:get_address())
            _G.__SSH_TERMINALS[paddr] = self
            print("[TerminalView] Registered mapping for parent/ancestor address: " .. paddr)
            curr = curr:getParent()
        end

        -- 注册帧更新（光标闪烁 + 轮询驱动）
        if view.registerFrameCallback then
            view:registerFrameCallback(function(dt)
                self:_onFrame(dt)
            end)
        end

        -- 视图销毁时清理引用
        if view.onWillDisappear then
            view:onWillDisappear(function()
                if _G.__SSH_TERMINALS then
                    _G.__SSH_TERMINALS[view:get_address()] = nil
                end
            end)
        end

        view:onPointerDown(function(event)
            return self:_onPointerDown(event)
        end)
        view:onPointerMove(function(event)
            return self:_onPointerMove(event)
        end)
        view:onPointerUp(function(event)
            return self:_onPointerUp(event)
        end)
        view:onScroll(function(event)
            if self._overlayKeyboardVisible then
                return true
            end
            if event.y ~= 0 then
                if event.y > 0 then self:scrollUp(3) else self:scrollDown(3) end
                return true
            end
            return false
        end)
    end
end

-- ── 全局物理键盘事件监听 (单例订阅，避免内存泄漏) ──────────────
local function initGlobalKeyboardListeners()
    local inputManager = brls.Application.getPlatform():getInputManager()
    if not inputManager or not inputManager.getCharInputEvent then return end
    local KEY_K = 75
    local MOD_CTRL = 0x02
    
    -- 防止重复初始化
    if _G.__SSH_TERMINAL_INPUT_INITED then return end
    _G.__SSH_TERMINAL_INPUT_INITED = true

    -- 字符输入
    inputManager:getCharInputEvent():subscribe(function(codepoint)
        local focus = brls.Application.getCurrentFocus()
        if focus and _G.__SSH_TERMINALS then
            local curr = focus
            local terminal = nil
            while curr do
                local addr = tostring(curr:get_address())
                terminal = _G.__SSH_TERMINALS[addr]
                if terminal then break end
                curr = curr:getParent()
            end

            if terminal then
                print("[TerminalView] Character input: " .. tostring(codepoint))
                terminal._keyboard:handleChar(codepoint)
            else
                print("[TerminalView] No mapping for focus addr: " .. tostring(focus:get_address()))
            end
        else
            print("[TerminalView] CharInput call ignored: no active focus or terminals")
        end
    end)

    -- 按键输入 (Enter, Backspace, Arrows, Ctrl+Keys)
    inputManager:getKeyboardKeyStateChanged():subscribe(function(state)
        if state.pressed then
            local focus = brls.Application.getCurrentFocus()
            print(string.format("[TerminalView] Global Key: key=%d mods=%d focus=%s", 
                state.key, state.mods, focus and tostring(focus:get_address()) or "nil"))
            
            if focus and _G.__SSH_TERMINALS then
                local curr = focus
                local terminal = nil
                while curr do
                    local addr = tostring(curr:get_address())
                    terminal = _G.__SSH_TERMINALS[addr]
                    if terminal then break end
                    curr = curr:getParent()
                end

                if terminal then
                    local ctrl = (state.mods % 4) >= 2
                    if ctrl and state.key == KEY_K then
                        terminal._overlayKeyboardVisible = not terminal._overlayKeyboardVisible
                        terminal:_invalidate()
                        return
                    end

                    terminal._keyboard:handleKey(state.key, state.mods)
                end
            end
        end
    end)
end

-- 尝试初始化（如果环境已就绪）
pcall(initGlobalKeyboardListeners)

-- ── 接收 SSH 数据并更新缓冲区 ────────────────────────────────
function TerminalView:feedData(data)
    if not data or #data == 0 then return end
    print("[TerminalView] feedData: " .. #data .. " bytes")
    local ops = self._parser:feed(data)
    for _, op in ipairs(ops) do
        if op.type == "dsr_report" then
            -- 响应光标报告 ESC[row;colR
            local resp = string.format("\27[%d;%dR", self._buf.curRow, self._buf.curCol)
            print("[TerminalView] Responding to DSR with: " .. resp)
            self:_sendInput(resp)
        else
            self._buf:_applyOp(op)
        end
    end

    -- 收到数据时自动滚动到底部
    self._scrollOffset = 0
    -- 标记视图需要重绘
    self:_invalidate()
    -- 记录日志
    if self._logEnabled then
        self._log[#self._log + 1] = {time=os.time(), raw=data}
        if #self._log > 1000 then table.remove(self._log, 1) end
    end
end

-- ── 处理连接状态变化 ─────────────────────────────────────────
function TerminalView:setStatus(text, r, g, b)
    self._statusText  = text
    self._statusColor = {r=r or 150, g=g or 150, b=b or 150}
    self:_invalidate()
end

-- ── 调整终端尺寸（窗口大小变化时调用）──────────────────────
function TerminalView:resize(width, height)
    local newCols = math.max(10, math.floor((width  - PADDING_X * 2) / CHAR_WIDTH))
    local newRows = math.max(4,  math.floor((height - PADDING_Y * 2 - 20) / LINE_HEIGHT))
    if newCols ~= self._cols or newRows ~= self._rows then
        self._cols = newCols
        self._rows = newRows
        self._buf:resize(newCols, newRows)
        self._ssh:resize(newCols, newRows)
        print("[SSH Terminal] Resized to " .. newCols .. "x" .. newRows)
    end
end

function TerminalView:reset()
    self._parser = AnsiParser.new()
    self._buf = TerminalBuffer.new(self._cols, self._rows)
    self._scrollOffset = 0
    self._maxScroll = 0
    self._selection = nil
    self._selecting = false
    self._statusText = "未连接"
    self._statusColor = { r = 150, g = 150, b = 150 }
    self._overlayKeyboardVisible = false
    self._overlayBuffer = ""
    self._overlayShift = false
    self._overlayCaps = false
    self._overlayCtrl = false
    self._overlayAlt = false
    self._overlayTouchTargets = {}
    self._overlayPanelRect = nil
    self._overlaySelectedKey = OVERLAY_LAYOUT[2][2]
    self._overlayRecentCommands = {}
    self._buttonRepeatState = {}
    self._touchState = { pressed = false, x = 0, y = 0, id = -1 }
    self._overlayRumbleCooling = false
    self._overlayRumbleSeq = 0
    self:_invalidate()
end

local function _overlayTrim(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function TerminalView:_clearOverlayModifiers(clearCaps)
    self._overlayShift = false
    self._overlayCtrl = false
    self._overlayAlt = false
    if clearCaps then
        self._overlayCaps = false
    end
end

function TerminalView:_rememberCommand(command)
    command = _overlayTrim(command)
    if command == "" then return end

    local nextRecent = { command }
    for _, item in ipairs(self._overlayRecentCommands) do
        if item ~= command then
            table.insert(nextRecent, item)
        end
        if #nextRecent >= 8 then
            break
        end
    end
    self._overlayRecentCommands = nextRecent
end

function TerminalView:_appendOverlayText(text)
    if not text or text == "" then return end
    self:_sendInput(text)
    self._overlayBuffer = self._overlayBuffer .. text
    self:_invalidate()
end

function TerminalView:_applyOverlayModifiers(text)
    local out = text or ""

    if self._overlayCtrl and #out == 1 then
        local byte = string.byte(string.upper(out))
        if byte and byte >= 65 and byte <= 90 then
            out = string.char(byte - 64)
        end
    end

    if self._overlayAlt then
        out = Platform.keyMap.ESC .. out
    end

    self._overlayShift = false
    self._overlayCtrl = false
    self._overlayAlt = false
    return out
end

function TerminalView:_resolveOverlayChar(key)
    if key.letter then
        local useUpper = (self._overlayCaps and not self._overlayShift) or (self._overlayShift and not self._overlayCaps)
        return useUpper and string.upper(key.base) or string.lower(key.base)
    end

    if self._overlayShift and key.shift then
        return key.shift
    end

    return key.base or key.value or key.label
end

function TerminalView:_backspaceOverlayBuffer()
    self:_sendInput(Platform.keyMap.BS)
    if #self._overlayBuffer > 0 then
        self._overlayBuffer = string.sub(self._overlayBuffer, 1, #self._overlayBuffer - 1)
    end
    self._overlayShift = false
    self._overlayCtrl = false
    self._overlayAlt = false
    self:_invalidate()
end

function TerminalView:_submitOverlayBuffer()
    local command = _overlayTrim(self._overlayBuffer)
    if command ~= "" then
        self:_rememberCommand(command)
    end
    self:_sendInput(Platform.keyMap.ENTER)
    self._overlayBuffer = ""
    self:_clearOverlayModifiers(false)
    self:_invalidate()
end

function TerminalView:_syncOverlayBuffer(text)
    text = text or ""
    self:_sendInput(Platform.keyMap.CTRL_U)
    if #text > 0 then
        self:_sendInput(text)
    end
    self._overlayBuffer = text
    self:_clearOverlayModifiers(false)
    self:_invalidate()
end

function TerminalView:_activateOverlayKey(key)
    if not key then return end
    self._overlaySelectedKey = key
    self:_rumbleOverlayTap()

    if key.action == "char" then
        self:_appendOverlayText(self:_applyOverlayModifiers(self:_resolveOverlayChar(key)))
    elseif key.action == "text" then
        self:_appendOverlayText(self:_applyOverlayModifiers(key.value or key.label))
    elseif key.action == "space" then
        self:_appendOverlayText(self:_applyOverlayModifiers(" "))
    elseif key.action == "send" then
        self:_sendInput(self:_applyOverlayModifiers(key.value or ""))
        self:_invalidate()
    elseif key.action == "tab" then
        self:_sendInput(Platform.keyMap.TAB)
        self:_clearOverlayModifiers(false)
        self:_invalidate()
    elseif key.action == "enter" then
        self:_submitOverlayBuffer()
    elseif key.action == "backspace" then
        self:_backspaceOverlayBuffer()
    elseif key.action == "shift" then
        self._overlayShift = not self._overlayShift
        self:_invalidate()
    elseif key.action == "caps" then
        self._overlayCaps = not self._overlayCaps
        self:_invalidate()
    elseif key.action == "ctrl" then
        self._overlayCtrl = not self._overlayCtrl
        self:_invalidate()
    elseif key.action == "alt" then
        self._overlayAlt = not self._overlayAlt
        self:_invalidate()
    end
end

function TerminalView:_rumbleOverlayTap(kind)
    if not Platform.isSwitch then return end
    if self._overlayRumbleCooling then return end

    self._overlayRumbleCooling = true
    pcall(function()
        brls.delay(OVERLAY_RUMBLE_INTERVAL_MS, function()
            self._overlayRumbleCooling = false
        end)
    end)

    local low = OVERLAY_RUMBLE_LOW
    local high = OVERLAY_RUMBLE_HIGH
    if kind == "nav" then
        low = math.max(12000, math.floor(low * 0.55))
        high = math.max(22000, math.floor(high * 0.55))
    end

    self._overlayRumbleSeq = (self._overlayRumbleSeq or 0) + 1
    local seq = self._overlayRumbleSeq

    if brls.Application.pulseSwitchRumble then
        local okPulse, didPulse = pcall(function()
            return brls.Application.pulseSwitchRumble(low / 65535.0, high / 65535.0, OVERLAY_RUMBLE_PULSE_MS)
        end)
        if okPulse and didPulse then
            return
        end
    end

    local ok, inputManager = pcall(function()
        return brls.Application.getPlatform():getInputManager()
    end)

    if not ok or not inputManager or not inputManager.sendRumble then
        return
    end

    pcall(function()
        inputManager:sendRumble(0, low, high)
    end)

    pcall(function()
        brls.delay(OVERLAY_RUMBLE_PULSE_MS, function()
            if self._overlayRumbleSeq ~= seq then
                return
            end

            pcall(function()
                inputManager:sendRumble(0, 0, 0)
            end)
        end)
    end)

    self._lastOverlayRumbleAt = 0
end

function TerminalView:_collectOverlaySuggestions()
    local items = {}
    local seen = {}

    local function addItem(text, mode)
        if not text or text == "" or seen[text] then return end
        seen[text] = true
        table.insert(items, { text = text, mode = mode or "text" })
    end

    for _, cmd in ipairs(OVERLAY_QUICK_COMMANDS) do
        addItem(cmd, "replace")
    end
    for _, sym in ipairs(OVERLAY_QUICK_SYMBOLS) do
        addItem(sym, "text")
    end

    local prefix = self._overlayBuffer:match("([%w%._%-/]*)$") or ""
    local lowerPrefix = string.lower(prefix)

    if lowerPrefix ~= "" then
        for _, cmd in ipairs(self._overlayRecentCommands) do
            if string.sub(string.lower(cmd), 1, #lowerPrefix) == lowerPrefix then
                addItem(cmd, "replace")
            end
        end
        for _, cmd in ipairs(OVERLAY_COMMON_COMMANDS) do
            if string.sub(string.lower(cmd), 1, #lowerPrefix) == lowerPrefix then
                addItem(cmd, "replace")
            end
        end
    else
        for _, cmd in ipairs(self._overlayRecentCommands) do
            addItem(cmd, "replace")
        end
    end

    local limited = {}
    for i, item in ipairs(items) do
        limited[i] = item
        if i >= 12 then break end
    end
    return limited
end

function TerminalView:_applySuggestion(item)
    if not item then return end
    self:_rumbleOverlayTap()
    if item.mode == "replace" then
        self:_syncOverlayBuffer(item.text)
    else
        self:_appendOverlayText(item.text)
    end
end

function TerminalView:_findOverlayKeyPosition(target)
    if not target then
        return 2, 2
    end

    for rowIndex, row in ipairs(OVERLAY_LAYOUT) do
        for colIndex, key in ipairs(row) do
            if key == target then
                return rowIndex, colIndex
            end
        end
    end

    return 2, 2
end

function TerminalView:_moveOverlaySelection(dx, dy)
    local previous = self._overlaySelectedKey
    local rowIndex, colIndex = self:_findOverlayKeyPosition(self._overlaySelectedKey)
    local nextRow = math.max(1, math.min(#OVERLAY_LAYOUT, rowIndex + dy))
    local nextCol = colIndex + dx
    local row = OVERLAY_LAYOUT[nextRow]

    if nextCol < 1 then nextCol = 1 end
    if nextCol > #row then nextCol = #row end

    self._overlaySelectedKey = row[nextCol]
    if previous ~= self._overlaySelectedKey then
        self:_rumbleOverlayTap("nav")
    end
    self:_invalidate()
end

function TerminalView:_toLocalPoint(absX, absY)
    return absX - (self._drawX or 0), absY - (self._drawY or 0)
end

local function _nowMs()
    return math.floor(os.clock() * 1000)
end

function TerminalView:_openSystemIme()
    local editingOverlay = self._overlayKeyboardVisible
    self._keyboard:openSwkbd({
        header = editingOverlay and "SSH Command" or "SSH Input",
        guide = editingOverlay and "Edit current command buffer" or "Input a full command",
        initial = self._overlayBuffer,
        maxLen = 256,
        onSubmit = function(inputText)
            local text = inputText or ""
            if editingOverlay then
                self:_syncOverlayBuffer(text)
            else
                self._overlayBuffer = text
                if _overlayTrim(text) ~= "" then
                    self:_submitOverlayBuffer()
                else
                    self:_invalidate()
                end
            end
        end,
    })
end

function TerminalView:_handleOverlayActions(justPressed)
    local B = brls.ControllerButton

    local function triggered(button)
        return justPressed(button, true)
    end

    if triggered(B.BUTTON_UP) then
        self:_moveOverlaySelection(0, -1)
    end
    if triggered(B.BUTTON_DOWN) then
        self:_moveOverlaySelection(0, 1)
    end
    if triggered(B.BUTTON_LEFT) then
        self:_moveOverlaySelection(-1, 0)
    end
    if triggered(B.BUTTON_RIGHT) then
        self:_moveOverlaySelection(1, 0)
    end

    if justPressed(B.BUTTON_A) then
        self:_activateOverlayKey(self._overlaySelectedKey)
    end
    if justPressed(B.BUTTON_B) then
        self:_backspaceOverlayBuffer()
    end
    if justPressed(B.BUTTON_X) then
        self._overlayShift = not self._overlayShift
        self:_invalidate()
    end
    if justPressed(B.BUTTON_Y) then
        self:_appendOverlayText(self:_applyOverlayModifiers(" "))
    end
    if justPressed(B.BUTTON_LB) then
        self:_sendInput(Platform.keyMap.TAB)
        self:_clearOverlayModifiers(false)
    end
    if justPressed(B.BUTTON_START) then
        self:_openSystemIme()
    end
    if justPressed(B.BUTTON_RSB) or justPressed(B.BUTTON_RB) then
        self._overlayKeyboardVisible = false
        self:_invalidate()
    end
end

function TerminalView:_isPointInOverlay(absX, absY)
    local rect = self._overlayPanelRect
    if not rect then return false end
    return absX >= rect.x and absX <= rect.x + rect.w and absY >= rect.y and absY <= rect.y + rect.h
end

function TerminalView:_hitOverlayTarget(absX, absY)
    for i = #self._overlayTouchTargets, 1, -1 do
        local target = self._overlayTouchTargets[i]
        if absX >= target.x and absX <= target.x + target.w and absY >= target.y and absY <= target.y + target.h then
            return target
        end
    end
    return nil
end

function TerminalView:_pollOverlayTouch()
    if not self._overlayKeyboardVisible then
        self._touchState.pressed = false
        return
    end

    if not Platform.isSwitch or not brls.Application.getSwitchTouchState then
        return
    end

    local ok, touch = pcall(function()
        return brls.Application.getSwitchTouchState()
    end)

    if not ok or not touch then
        return
    end

    local wasPressed = self._touchState.pressed and true or false
    local isPressed = touch.pressed and true or false

    if isPressed then
        local target = self:_hitOverlayTarget(touch.x, touch.y)
        if target and target.type == "key" then
            self._overlaySelectedKey = target.key
            if not wasPressed or self._touchState.id ~= touch.id then
                self:_activateOverlayKey(target.key)
            end
        elseif target and target.type == "suggestion" then
            if not wasPressed or self._touchState.id ~= touch.id then
                self:_applySuggestion(target.item)
            end
        end
    end

    self._touchState = {
        pressed = isPressed,
        x = touch.x or 0,
        y = touch.y or 0,
        id = touch.id or -1,
    }
end

-- ── 帧更新（光标闪烁）────────────────────────────────────────
local function _pollPressed(button)
    local pollFn = nil

    if Platform.isSwitch and brls.Application.isSwitchControllerButtonPressed then
        pollFn = brls.Application.isSwitchControllerButtonPressed
    elseif brls.Application.isControllerButtonPressed then
        pollFn = brls.Application.isControllerButtonPressed
    end

    if not pollFn then
        return false, "no-button-api"
    end

    local ok, pressed = pcall(function()
        return pollFn(button)
    end)

    if not ok then
        return false, tostring(pressed)
    end

    return pressed and true or false, nil
end

function TerminalView:_pollControllerShortcuts()
    self._debugFrameCount = self._debugFrameCount + 1

    if not Platform.isSwitch then
        self._debugButtonsText = "DBG platform=desktop"
        return
    end

    if not brls.Application.isSwitchControllerButtonPressed and not brls.Application.isControllerButtonPressed then
        self._debugButtonsText = "DBG no-button-api"
        return
    end

    local B = brls.ControllerButton
    local watched = {
        B.BUTTON_A,
        B.BUTTON_B,
        B.BUTTON_X,
        B.BUTTON_Y,
        B.BUTTON_LB,
        B.BUTTON_RB,
        B.BUTTON_RSB,
        B.BUTTON_UP,
        B.BUTTON_DOWN,
        B.BUTTON_LEFT,
        B.BUTTON_RIGHT,
        B.BUTTON_START,
        B.BUTTON_BACK,
    }

    local current = {}
    local errors = {}
    for _, button in ipairs(watched) do
        local pressed, err = _pollPressed(button)
        current[button] = pressed
        if err then
            table.insert(errors, err)
        end
    end

    local pollMode = (Platform.isSwitch and brls.Application.isSwitchControllerButtonPressed) and "raw" or "brls"
    local rawButtons = brls.Application.getSwitchButtonsDebug and brls.Application.getSwitchButtonsDebug() or "n/a"

    self._debugButtonsText = string.format(
        "DBG[%s] A=%d B=%d X=%d Y=%d L=%d R=%d R3=%d +=%d -=%d F=%d RAW=%s",
        pollMode,
        current[B.BUTTON_A] and 1 or 0,
        current[B.BUTTON_B] and 1 or 0,
        current[B.BUTTON_X] and 1 or 0,
        current[B.BUTTON_Y] and 1 or 0,
        current[B.BUTTON_LB] and 1 or 0,
        current[B.BUTTON_RB] and 1 or 0,
        current[B.BUTTON_RSB] and 1 or 0,
        current[B.BUTTON_START] and 1 or 0,
        current[B.BUTTON_BACK] and 1 or 0,
        self._debugFrameCount,
        rawButtons)
    self._debugPollText = (#errors > 0) and ("ERR " .. table.concat(errors, " | ")) or ""

    local nowMs = _nowMs()
    local function justPressed(button, allowRepeat)
        local wasPressed = self._lastPolledButtons[button] and true or false
        local isPressed = current[button] and true or false
        local state = self._buttonRepeatState[button] or { nextAt = 0 }

        if isPressed and not wasPressed then
            state.nextAt = nowMs + DPAD_REPEAT_DELAY_MS
            self._buttonRepeatState[button] = state
            return true
        end

        if (not isPressed) then
            state.nextAt = 0
            self._buttonRepeatState[button] = state
            return false
        end

        if allowRepeat and state.nextAt > 0 and nowMs >= state.nextAt then
            state.nextAt = nowMs + DPAD_REPEAT_INTERVAL_MS
            self._buttonRepeatState[button] = state
            return true
        end

        self._buttonRepeatState[button] = state
        return false
    end

    if self._overlayKeyboardVisible then
        self:_handleOverlayActions(justPressed)
        self._lastPolledButtons = current
        return
    end

    if justPressed(B.BUTTON_UP, true) then
        self:_sendInput(Platform.keyMap.UP)
    end
    if justPressed(B.BUTTON_DOWN, true) then
        self:_sendInput(Platform.keyMap.DOWN)
    end
    if justPressed(B.BUTTON_LEFT, true) then
        self:_sendInput(Platform.keyMap.LEFT)
    end
    if justPressed(B.BUTTON_RIGHT, true) then
        self:_sendInput(Platform.keyMap.RIGHT)
    end

    if justPressed(B.BUTTON_A) then
        _trace("[TerminalView] Polled A -> Enter")
        self:_sendInput(Platform.keyMap.ENTER)
    end
    if justPressed(B.BUTTON_B) then
        _trace("[TerminalView] Polled B -> Delete")
        self:_sendInput(Platform.keyMap.BS)
    end
    if justPressed(B.BUTTON_X) then
        _trace("[TerminalView] Polled X -> Ctrl+C")
        self:_sendInput(Platform.keyMap.CTRL_C)
    end
    if justPressed(B.BUTTON_Y) then
        _trace("[TerminalView] Polled Y -> EOF")
        self:_sendInput(Platform.keyMap.CTRL_D)
    end
    if justPressed(B.BUTTON_LB) then
        _trace("[TerminalView] Polled L -> Tab")
        self:_sendInput(Platform.keyMap.TAB)
    end
    if justPressed(B.BUTTON_RSB) or justPressed(B.BUTTON_RB) then
        _trace("[TerminalView] Polled R3 -> Overlay Keyboard")
        self._overlayKeyboardVisible = not self._overlayKeyboardVisible
        self:_rumbleOverlayTap("nav")
        self:_invalidate()
    end
    if justPressed(B.BUTTON_START) then
        _trace("[TerminalView] Polled + -> System IME")
        self:_openSystemIme()
    end
    if justPressed(B.BUTTON_BACK) then
        _trace("[TerminalView] Polled - -> Close")
        if self._onCloseRequest then
            self._onCloseRequest()
        elseif self._ssh:isConnected() then
            self._ssh:disconnect()
        end
    end

    self._lastPolledButtons = current
end

function TerminalView:_drawKeyboardOverlay(vg, x, y, w, h)
    local panelH = math.floor(h * 0.54)
    if panelH < 344 then panelH = 344 end
    local panelY = y + h - panelH - 4
    local panelX = x + 12
    local panelW = w - 24
    local headerH = 30
    local chipsH = 56
    local footerH = 0
    local rowGap = 2
    local keyGap = 4
    local rows = OVERLAY_LAYOUT
    local rowAreaH = panelH - headerH - chipsH - footerH - 8
    local keyH = math.floor((rowAreaH - rowGap * (#rows - 1)) / #rows)
    if keyH < 46 then keyH = 46 end

    self._overlayTouchTargets = {}
    self._overlayPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 14)
    nvgFillColor(vg, nvgRGBA(18, 18, 22, 242))
    nvgFill(vg)

    nvgFontFace(vg, "regular")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
    nvgText(vg, panelX + 14, panelY + headerH / 2, "Touch Keyboard")

    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(185, 185, 185, 255))
    nvgText(vg, panelX + panelW / 2, panelY + headerH / 2, OVERLAY_HINT_TEXT)

    local modeText = string.format("Shift:%s Caps:%s Ctrl:%s Alt:%s", self._overlayShift and "1" or "0", self._overlayCaps and "1" or "0", self._overlayCtrl and "1" or "0", self._overlayAlt and "1" or "0")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(120, 180, 255, 255))
    nvgText(vg, panelX + panelW - 14, panelY + headerH / 2, modeText)

    local suggestions = self:_collectOverlaySuggestions()
    local chipX = panelX + 12
    local chipY = panelY + headerH + 6
    for index, item in ipairs(suggestions) do
        local label = item.text
        local chipW = math.min(panelW * 0.26, math.max(70, 30 + #label * 10))
        if chipX + chipW > panelX + panelW - 12 then
            break
        end

        local chipPalette = _overlayChipPalette(index, item)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, chipX, chipY, chipW, chipsH - 6, 10)
        nvgFillColor(vg, chipPalette.fill)
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, chipX + 0.5, chipY + 0.5, chipW - 1, chipsH - 7, 10)
        nvgStrokeColor(vg, chipPalette.border)
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)

        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, chipPalette.text)
        nvgText(vg, chipX + chipW / 2, chipY + (chipsH - 6) / 2, label)

        table.insert(self._overlayTouchTargets, {
            x = chipX,
            y = chipY,
            w = chipW, h = chipsH - 6,
            type = "suggestion", item = item,
        })

        chipX = chipX + chipW + 6
    end

    local rowY = panelY + headerH + chipsH + 6
    local contentW = panelW - 24
    for rowIndex, row in ipairs(rows) do
        local units = 0
        for _, key in ipairs(row) do
            units = units + (key.width or 1)
        end
        local keyUnitW = (contentW - keyGap * (#row - 1)) / units
        local keyX = panelX + 12

        for _, key in ipairs(row) do
            local keyW = keyUnitW * (key.width or 1)
            local selected = (self._overlaySelectedKey == key)
            local active = (key.action == "shift" and self._overlayShift)
                or (key.action == "caps" and self._overlayCaps)
                or (key.action == "ctrl" and self._overlayCtrl)
                or (key.action == "alt" and self._overlayAlt)
            local palette = _overlayKeyPalette(key, rowIndex, selected, active)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, keyX, rowY, keyW, keyH, 7)
            nvgFillColor(vg, palette.fill)
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, keyX + 0.6, rowY + 0.6, keyW - 1.2, keyH - 1.2, 7)
            nvgStrokeColor(vg, palette.border)
            nvgStrokeWidth(vg, (selected or active) and 2.0 or 1.2)
            nvgStroke(vg)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, keyX + 2, rowY + 2, keyW - 4, math.max(6, keyH * 0.22), 5)
            nvgFillColor(vg, palette.top)
            nvgFill(vg)

            local label = key.label
            if key.action == "char" then
                label = self:_resolveOverlayChar(key)
            end

            nvgFontSize(vg, keyH >= 46 and 18 or 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, palette.text)
            nvgText(vg, keyX + keyW / 2, rowY + keyH / 2, label)

            table.insert(self._overlayTouchTargets, {
                x = keyX,
                y = rowY,
                w = keyW, h = keyH,
                type = "key", key = key,
            })

            keyX = keyX + keyW + keyGap
        end

        rowY = rowY + keyH + rowGap
    end

end

function TerminalView:_onFrame(dt)
    self:_pollControllerShortcuts()
    self:_pollOverlayTouch()

    self._blinkTimer = self._blinkTimer + dt
    if self._blinkTimer >= CURSOR_BLINK_INTERVAL then
        self._blinkTimer = self._blinkTimer - CURSOR_BLINK_INTERVAL
        self._blinkOn = not self._blinkOn
        self:_invalidate()
    end
end

-- ── NanoVG 绘制主函数 ────────────────────────────────────────
function TerminalView:_draw(vg, x, y, w, h)
    self._drawX = x or 0
    self._drawY = y or 0
    self._drawW = w or 0
    self._drawH = h or 0

    -- 如果没有 registerFrameCallback，在绘制函数里手动更新时间步长（粗略估计 16ms）
    if not self._view.registerFrameCallback then
        self:_onFrame(0.016)
    end

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(BG_R, BG_G, BG_B, 255))
    nvgFill(vg)

    -- 字体设置（使用等宽字体）
    nvgFontSize(vg, FONT_SIZE)
    nvgFontFace(vg, "monospace")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 可见行数
    local visRows = math.min(self._rows, math.floor((h - PADDING_Y * 2 - 20) / LINE_HEIGHT))

    -- 计算整体显示范围（从 1 到 histLen + rows）
    local histLen = #self._buf.history
    local totalRows = histLen + self._rows
    local startLine = totalRows - self._scrollOffset - visRows + 1
    if startLine < 1 then startLine = 1 end

    local startHistRow = 1
    local startScreenRow = 1

    if startLine <= histLen then
        startHistRow = startLine
        startScreenRow = 1
    else
        startHistRow = histLen + 1 -- 无需绘制历史
        startScreenRow = startLine - histLen
    end

    -- 绘制选择背景（如果在当前视野内）
    if self._selection then
        self:_drawSelection(vg, x, y, w, h, startLine, visRows)
    end

    -- 绘制历史行
    local drawY = y + PADDING_Y
    if self._scrollOffset > 0 then
        for hi = startHistRow, histLen do
            if drawY > y + h - 20 then break end
            self:_drawRow(vg, x + PADDING_X, drawY, self._buf.history[hi])
            drawY = drawY + LINE_HEIGHT
        end
    end

    -- 绘制屏幕行
    for r = startScreenRow, self._rows do
        if drawY > y + h - 20 then break end
        local row = self._buf.screen[r]
        if row then
            self:_drawRow(vg, x + PADDING_X, drawY, row)
        end
        -- 绘制光标（仅底部区域，无滚动偏移时）
        if self._scrollOffset == 0 and r == self._buf.curRow and
           self._blinkOn and self._buf.cursorVisible then
            local cx = x + PADDING_X + (self._buf.curCol - 1) * CHAR_WIDTH
            nvgBeginPath(vg)
            -- local cw = cell.wide and WIDE_CHAR_WIDTH or CHAR_WIDTH
            -- nvgRect(vg, cx, drawY, cw, LINE_HEIGHT)
            nvgRect(vg, cx, drawY, CHAR_WIDTH, LINE_HEIGHT)
            nvgFillColor(vg, nvgRGBA(220, 220, 220, 180))
            nvgFill(vg)
        end
        drawY = drawY + LINE_HEIGHT
    end

    -- 状态栏（底部）
    self:_drawStatusBar(vg, x, y + h - 20, w, 20)

    if self._overlayKeyboardVisible then
        self:_drawKeyboardOverlay(vg, x, y, w, h)
    end

    -- 滚动位置指示器
    if self._scrollOffset > 0 then
        self:_drawScrollIndicator(vg, x + w - 8, y, 6, h - 20)
    end
end

-- ── 绘制单行 ────────────────────────────────────────────────
function TerminalView:_drawRow(vg, x, y, row)
    if not row then return end
    local cx = x
    local prevAttr = nil

    for c = 1, self._cols do
        local cell = row[c]
        if not cell or cell.widePlaceholder then
            cx = cx + CHAR_WIDTH
        else
            local attr = cell.attr
            local ch   = cell.ch or " "

            local cw = cell.wide and WIDE_CHAR_WIDTH or CHAR_WIDTH
            -- 背景色（非默认时才绘制）
            local bg = attr.bg
            if bg.r ~= BG_R or bg.g ~= BG_G or bg.b ~= BG_B then
                nvgBeginPath(vg)
                nvgRect(vg, cx, y, cw, LINE_HEIGHT)
                nvgFillColor(vg, nvgRGBA(bg.r, bg.g, bg.b, 255))
                nvgFill(vg)
            end

            -- 前景色 + 文字绘制
            if ch ~= " " and not attr.invisible then
                local fg = attr.reverse and attr.bg or attr.fg
                nvgFillColor(vg, nvgRGBA(fg.r, fg.g, fg.b, fg.a or 255))
                if attr.bold then
                    nvgFontBlur(vg, 0)
                    -- 粗体通过偏移绘制两次模拟（简单实现）
                    nvgText(vg, cx + 0.5, y, ch)
                end
                nvgText(vg, cx, y, ch)
            end

            -- 下划线
            if attr.underline then
                nvgBeginPath(vg)
                nvgMoveTo(vg, cx, y + LINE_HEIGHT - 2)
                nvgLineTo(vg, cx + CHAR_WIDTH, y + LINE_HEIGHT - 2)
                local fg = attr.fg
                nvgStrokeColor(vg, nvgRGBA(fg.r, fg.g, fg.b, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end

            cx = cx + (cell.wide and WIDE_CHAR_WIDTH or CHAR_WIDTH)
        end
    end
end

-- ── 绘制底部状态栏 ───────────────────────────────────────────
function TerminalView:_drawStatusBar(vg, x, y, w, h)
    -- ??
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(30, 30, 30, 230))
    nvgFill(vg)

    nvgFontFace(vg, "regular")

    -- ????
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local c = self._statusColor
    nvgFillColor(vg, nvgRGBA(c.r, c.g, c.b, 255))
    nvgText(vg, x + 4, y + h / 2, self._statusText)

    local hintText = Platform.isSwitch and SWITCH_HINT_TEXT or DESKTOP_HINT_TEXT
    if hintText and hintText ~= "" then
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 220))
        nvgText(vg, x + w / 2, y + h / 2 - 5, hintText)
    end

    if Platform.isSwitch and self._debugButtonsText then
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 180, 80, 230))
        nvgText(vg, x + w / 2, y + h / 2 + 5, self._debugButtonsText)
    end

    -- ??????
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 100, 100, 255))
    nvgText(vg, x + w - 4, y + h / 2,
        string.format("%dx%d", self._cols, self._rows))
end

function TerminalView:_drawScrollIndicator(vg, x, y, w, h)
    local total = #self._buf.history + self._rows
    if total <= self._rows then return end
    local ratio  = self._rows / total
    local barH   = math.max(20, h * ratio)
    local posRatio = (total - self._rows - self._scrollOffset) / (total - self._rows)
    local barY   = y + (h - barH) * posRatio

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, barY, w, barH, w / 2)
    nvgFillColor(vg, nvgRGBA(150, 150, 150, 120))
    nvgFill(vg)
end

-- ── 向 SSH 发送输入 ──────────────────────────────────────────
function TerminalView:_sendInput(data)
    if self._ssh and self._ssh.send then
        print("[TerminalView] Sending input: '" .. data:gsub("\r", "\\r"):gsub("\n", "\\n") .. "' (" .. #data .. " bytes)")
        local ok = self._ssh:send(data)
        if not ok then
            _trace("[TerminalView] send() returned false")
        end
    end
    -- 收到输入时滚动到底部
    self._scrollOffset = 0
end

-- ── 请求视图重绘 ─────────────────────────────────────────────
function TerminalView:_invalidate()
    if self._view then
        self._view:invalidate()
    end
end

-- ── 滚动历史缓冲区 ───────────────────────────────────────────
function TerminalView:scrollUp(lines)
    lines = lines or 3
    local maxOff = #self._buf.history
    self._scrollOffset = math.min(self._scrollOffset + lines, maxOff)
    self:_invalidate()
end

function TerminalView:scrollDown(lines)
    lines = lines or 3
    self._scrollOffset = math.max(0, self._scrollOffset - lines)
    self:_invalidate()
end

-- ── 鼠标/指针事件处理 ─────────────────────────────────────────
function TerminalView:_onPointerDown(event)
    local localEventX, localEventY = self:_toLocalPoint(event.x, event.y)

    if self._overlayKeyboardVisible then
        return true
    end

    -- 计算点击的行列
    local histLen = #self._buf.history
    local visRows = math.floor(((self._drawH > 0 and self._drawH or self._view:getHeight()) - PADDING_Y * 2 - 20) / LINE_HEIGHT)
    local totalRows = histLen + self._rows
    local startLine = totalRows - self._scrollOffset - visRows + 1
    if startLine < 1 then startLine = 1 end

    local localX = localEventX - PADDING_X
    local localY = localEventY - PADDING_Y
    
    local r = math.floor(localY / LINE_HEIGHT) + startLine
    local c = math.floor(localX / CHAR_WIDTH) + 1
    
    self._selection = { startRow = r, startCol = c, endRow = r, endCol = c }
    self._selecting = true
    self:_invalidate()
    return true
end

function TerminalView:_onPointerMove(event)
    local localEventX, localEventY = self:_toLocalPoint(event.x, event.y)

    if self._overlayKeyboardVisible then
        return true
    end

    if not self._selecting then return false end
    
    local histLen = #self._buf.history
    local visRows = math.floor(((self._drawH > 0 and self._drawH or self._view:getHeight()) - PADDING_Y * 2 - 20) / LINE_HEIGHT)
    local totalRows = histLen + self._rows
    local startLine = totalRows - self._scrollOffset - visRows + 1
    if startLine < 1 then startLine = 1 end

    local localX = localEventX - PADDING_X
    local localY = localEventY - PADDING_Y
    
    local r = math.floor(localY / LINE_HEIGHT) + startLine
    local c = math.floor(localX / CHAR_WIDTH) + 1
    
    self._selection.endRow = r
    self._selection.endCol = c
    self:_invalidate()
    return true
end

function TerminalView:_onPointerUp(event)
    local localEventX, localEventY = self:_toLocalPoint(event.x, event.y)

    if self._overlayKeyboardVisible then
        return true
    end

    if not self._selecting then return false end
    self._selecting = false
    
    -- 如果是简单的点击（没拖拽），清除选择
    if self._selection.startRow == self._selection.endRow and 
       math.abs(self._selection.startCol - self._selection.endCol) < 2 then
        self._selection = nil
    else
        -- 复制到剪贴板
        local text = self:getSelectedText()
        if text and #text > 0 then
            brls.Application.getPlatform():setClipboard(text)
            self:setStatus("已复制到剪贴板", 100, 255, 100)
            -- 1.5秒后恢复状态
            brls.get_timer():once(1500, function()
                self:setStatus(self._ssh:isConnected() and "已连接" or "未连接")
            end)
        end
    end
    
    self:_invalidate()
    return true
end

-- ── 获取选中的文本 ───────────────────────────────────────────
function TerminalView:getSelectedText()
    if not self._selection then return nil end
    local s = self._selection
    local r1, c1, r2, c2 = s.startRow, s.startCol, s.endRow, s.endCol
    if r1 > r2 or (r1 == r2 and c1 > c2) then
        r1, c1, r2, c2 = r2, c2, r1, c1
    end
    
    local histLen = #self._buf.history
    local lyrics = {}
    
    for r = r1, r2 do
        local rowData
        if r <= histLen then
            rowData = self._buf.history[r]
        else
            rowData = self._buf.screen[r - histLen]
        end
        
        if rowData then
            local lineText = ""
            local cs = (r == r1) and c1 or 1
            local ce = (r == r2) and c2 or self._cols
            for c = math.max(1, cs), math.min(self._cols, ce) do
                local cell = rowData[c]
                if cell and cell.ch and not cell.widePlaceholder then
                    lineText = lineText .. cell.ch
                end
            end
            table.insert(lyrics, lineText)
        end
    end
    return table.concat(lyrics, "\n")
end

-- ── 绘制选择高亮 ─────────────────────────────────────────────
function TerminalView:_drawSelection(vg, x, y, w, h, startLine, visRows)
    local s = self._selection
    local r1, c1, r2, c2 = s.startRow, s.startCol, s.endRow, s.endCol
    if r1 > r2 or (r1 == r2 and c1 > c2) then
        r1, c1, r2, c2 = r2, c2, r1, c1
    end
    
    local endLine = startLine + visRows - 1
    
    nvgBeginPath(vg)
    for r = math.max(r1, startLine), math.min(r2, endLine) do
        local cs = (r == r1) and c1 or 1
        local ce = (r == r2) and c2 or self._cols
        
        local rx = x + PADDING_X + (cs - 1) * CHAR_WIDTH
        local ry = y + PADDING_Y + (r - startLine) * LINE_HEIGHT
        local rw = (ce - cs + 1) * CHAR_WIDTH
        
        nvgRect(vg, rx, ry, rw, LINE_HEIGHT)
    end
    nvgFillColor(vg, nvgRGBA(100, 150, 255, 100))
    nvgFill(vg)
end

return TerminalView
