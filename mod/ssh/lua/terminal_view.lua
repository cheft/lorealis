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

local FONT_SIZE   = 16
local LINE_HEIGHT = 18
local CHAR_WIDTH  = 9
local WIDE_CHAR_WIDTH = 10
local PADDING_X   = 10
local PADDING_Y   = 10
local CURSOR_BLINK_RATE = 0.5
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

-- OVERLAY_THEME.panel_*：面板底色、边框、阴影
-- OVERLAY_THEME.row_colors：每一排普通键的底色
-- OVERLAY_THEME.special.*：Enter、Backspace、方向键、Space 这些功能键颜色
-- OVERLAY_THEME.state.*：选中框、激活态、提亮强度
-- OVERLAY_THEME.chip_colors：候选/标签色，后续恢复候选栏时直接可用
local OVERLAY_THEME = {
    panel_fill = { 248, 250, 253 },
    panel_border = { 217, 224, 235 },
    panel_shadow = { 120, 138, 168 },
    title_text = { 86, 97, 118 },
    hint_text = { 128, 137, 154 },
    mode_text = { 88, 146, 228 },
    key_text = { 72, 80, 96 },
    key_text_active = { 54, 62, 78 },
    row_colors = {
        { 255, 255, 255 },
        { 244, 249, 255 },
        { 245, 252, 248 },
        { 255, 248, 244 },
        { 247, 245, 255 },
    },
    special = {
        enter = { 183, 225, 255 },
        backspace = { 255, 212, 216 },
        shift_caps = { 226, 215, 255 },
        ctrl_alt = { 214, 233, 255 },
        system = { 228, 233, 241 },
        tab = { 210, 241, 228 },
        space = { 207, 232, 255 },
        arrows = { 220, 228, 239 },
        symbol = { 255, 229, 204 },
    },
    state = {
        fill_lift = 8,
        top_lift = 20,
        border_lift = 10,
        selected_border = { 118, 176, 255 },
        active_border = { 92, 156, 244 },
        selected_fill_lift = 4,
        active_fill_lift = 10,
    },
    chip_colors = {
        { 219, 235, 255 },
        { 217, 243, 232 },
        { 255, 233, 214 },
        { 234, 225, 255 },
        { 255, 221, 229 },
    },
}

local function _withAlpha(color, alpha)
    return nvgRGBA(color[1], color[2], color[3], alpha or 255)
end

local function _liftColor(color, amount)
    return {
        math.min(255, color[1] + amount),
        math.min(255, color[2] + amount),
        math.min(255, color[3] + amount),
    }
end

local function _overlayKeyPalette(key, rowIndex, selected, active)
    local theme = OVERLAY_THEME
    local base = theme.row_colors[rowIndex] or theme.row_colors[#theme.row_colors]

    if key.action == "enter" then
        base = theme.special.enter
    elseif key.action == "backspace" then
        base = theme.special.backspace
    elseif key.action == "shift" or key.action == "caps" then
        base = theme.special.shift_caps
    elseif key.action == "ctrl" or key.action == "alt" then
        base = theme.special.ctrl_alt
    elseif key.action == "cn" or key.action == "meta" or key.action == "fn" then
        base = theme.special.system
    elseif key.action == "tab" then
        base = theme.special.tab
    elseif key.action == "space" then
        base = theme.special.space
    elseif key.action == "send" then
        base = theme.special.arrows
    elseif key.action == "text" then
        base = theme.special.symbol
    end

    local fill = _liftColor(base, theme.state.fill_lift)
    local border = _liftColor(base, theme.state.border_lift)
    local top = _liftColor(base, theme.state.top_lift)
    local text_color = theme.key_text

    if active then
        fill = _liftColor(fill, theme.state.active_fill_lift)
        border = theme.state.active_border
        text_color = theme.key_text_active
    elseif selected then
        fill = _liftColor(fill, theme.state.selected_fill_lift)
        border = theme.state.selected_border
        text_color = theme.key_text_active
    end

    return {
        fill = _withAlpha(fill, 244),
        border = _withAlpha(border, 252),
        top = _withAlpha(top, 230),
        text = _withAlpha(text_color, 255),
    }
end

local function _overlayChipPalette(index, item)
    local theme = OVERLAY_THEME
    local base = theme.chip_colors[((index - 1) % #theme.chip_colors) + 1]
    if item and item.mode == "replace" then
        base = _liftColor(base, 8)
    end

    return {
        fill = _withAlpha(base, 238),
        border = _withAlpha(_liftColor(base, 10), 248),
        text = _withAlpha(theme.key_text, 255),
    }
end

local OVERLAY_QUICK_COMMANDS = { "ls", "cd", "pwd", "clear" }
local OVERLAY_QUICK_SYMBOLS = { "~", "$", "*", "|", "&&" }
local OVERLAY_COMMON_COMMANDS = {
    "ls", "cd", "pwd", "clear", "cat", "echo", "mkdir", "rm", "cp", "mv",
    "touch", "grep", "find", "git", "top", "htop", "vim", "nano", "ssh", "scp",
}

local ARROW_UP_LABEL = "\226\134\145"
local ARROW_LEFT_LABEL = "\226\134\144"
local ARROW_DOWN_LABEL = "\226\134\147"
local ARROW_RIGHT_LABEL = "\226\134\146"

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
        _key("?", { action = "char", base = "?", shift = "/" }),
        _key(ARROW_UP_LABEL, { action = "send", value = Platform.keyMap.UP, width = 1.15 }),
        _key("`", { action = "char", base = "~", shift = "`", width = 1.15 }),
    },
    {
        _key("中/EN", { action = "cn", width = 1.15 }),
        _key("Ctrl", { action = "ctrl", width = 1.15 }),
        _key("Win", { action = "meta", width = 1.15 }),
        _key("Alt", { action = "alt", width = 1.15 }),
        _key("Space", { action = "space", width = 5.5 }),
        _key("Fn", { action = "fn", width = 1.15 }),
        
        _key(ARROW_LEFT_LABEL, { action = "send", value = Platform.keyMap.LEFT, width = 1.15 }),
        _key(ARROW_DOWN_LABEL, { action = "send", value = Platform.keyMap.DOWN, width = 1.15 }),
        _key(ARROW_RIGHT_LABEL, { action = "send", value = Platform.keyMap.RIGHT, width = 1.15 }),
    },
}

local BG_R, BG_G, BG_B = 12, 12, 12

---@param sshManager SSHManager
function TerminalView.new(sshManager)
    local self = setmetatable({}, TerminalView)

    self._ssh      = sshManager
    self._parser   = AnsiParser.new()
    self._cols     = Platform.defaultCols
    self._rows     = Platform.defaultRows
    self._buf      = TerminalBuffer.new(self._cols, self._rows)
    self._keyboard = Keyboard.new(function(data) self:_sendInput(data) end)

    self._view     = nil

    self._cursorVisible  = true
    self._blinkTimer     = 0
    self._blinkOn        = true

    self._scrollOffset   = 0
    self._maxScroll      = 0

    self._statusText     = "æœªè¿žæŽ¥"
    self._statusColor    = {r=150, g=150, b=150}

    self._selection      = nil
    self._selecting      = false

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

function TerminalView:bindView(view)
    self._view = view
    if view then
        view:setDrawCallback(function(vg, x, y, w, h, style, ctx)
            self:_draw(vg, x, y, w, h)
        end)
        
        if view.setFocusable then
            view:setFocusable(true)
        end
        
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
        _G.__SSH_TERMINALS = _G.__SSH_TERMINALS or {}
        local addr = tostring(view:get_address())
        _G.__SSH_TERMINALS[addr] = self
        print("[TerminalView] Registered mapping for address: " .. addr)

        local curr = view:getParent()
        while curr do
            local paddr = tostring(curr:get_address())
            _G.__SSH_TERMINALS[paddr] = self
            print("[TerminalView] Registered mapping for parent/ancestor address: " .. paddr)
            curr = curr:getParent()
        end

        if view.registerFrameCallback then
            view:registerFrameCallback(function(dt)
                self:_onFrame(dt)
            end)
        end

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

local function initGlobalKeyboardListeners()
    local inputManager = brls.Application.getPlatform():getInputManager()
    if not inputManager or not inputManager.getCharInputEvent then return end
    local KEY_K = 75
    local MOD_CTRL = 0x02
    
    if _G.__SSH_TERMINAL_INPUT_INITED then return end
    _G.__SSH_TERMINAL_INPUT_INITED = true

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

pcall(initGlobalKeyboardListeners)

function TerminalView:feedData(data)
    if not data or #data == 0 then return end
    print("[TerminalView] feedData: " .. #data .. " bytes")
    local ops = self._parser:feed(data)
    for _, op in ipairs(ops) do
        if op.type == "dsr_report" then
            local resp = string.format("\27[%d;%dR", self._buf.curRow, self._buf.curCol)
            print("[TerminalView] Responding to DSR with: " .. resp)
            self:_sendInput(resp)
        else
            self._buf:_applyOp(op)
        end
    end

    self._scrollOffset = 0
    self:_invalidate()
    if self._logEnabled then
        self._log[#self._log + 1] = {time=os.time(), raw=data}
        if #self._log > 1000 then table.remove(self._log, 1) end
    end
end

function TerminalView:setStatus(text, r, g, b)
    self._statusText  = text
    self._statusColor = {r=r or 150, g=g or 150, b=b or 150}
    self:_invalidate()
end

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
    self._statusText = "æœªè¿žæŽ¥"
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
    elseif key.action == "cn" or key.action == "meta" or key.action == "fn" then
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
    local chipsH = 0
    local footerH = 0
    local rowGap = 2
    local keyGap = 4
    local rows = OVERLAY_LAYOUT
    local rowAreaH = panelH - headerH - chipsH - footerH - 6
    local keyH = math.floor((rowAreaH - rowGap * (#rows - 1)) / #rows)
    if keyH < 54 then keyH = 54 end

    self._overlayTouchTargets = {}
    self._overlayPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX + 1, panelY + 2, panelW, panelH, 14)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.panel_shadow, 32))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 14)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.panel_fill, 245))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX + 0.5, panelY + 0.5, panelW - 1, panelH - 1, 14)
    nvgStrokeColor(vg, _withAlpha(OVERLAY_THEME.panel_border, 255))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    nvgFontFace(vg, "regular")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.title_text, 255))
    nvgText(vg, panelX + 14, panelY + headerH / 2, "Touch Keyboard")

    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.hint_text, 255))
    nvgText(vg, panelX + panelW / 2, panelY + headerH / 2, OVERLAY_HINT_TEXT)

    local modeText = string.format("Shift:%s Caps:%s Ctrl:%s Alt:%s", self._overlayShift and "1" or "0", self._overlayCaps and "1" or "0", self._overlayCtrl and "1" or "0", self._overlayAlt and "1" or "0")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.mode_text, 255))
    nvgText(vg, panelX + panelW - 14, panelY + headerH / 2, modeText)

    local rowY = panelY + headerH + 4
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

function TerminalView:_draw(vg, x, y, w, h)
    self._drawX = x or 0
    self._drawY = y or 0
    self._drawW = w or 0
    self._drawH = h or 0

    if not self._view.registerFrameCallback then
        self:_onFrame(0.016)
    end

    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(BG_R, BG_G, BG_B, 255))
    nvgFill(vg)

    nvgFontSize(vg, FONT_SIZE)
    nvgFontFace(vg, "monospace")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    local visRows = math.min(self._rows, math.floor((h - PADDING_Y * 2 - 20) / LINE_HEIGHT))

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
        startHistRow = histLen + 1
        startScreenRow = startLine - histLen
    end

    if self._selection then
        self:_drawSelection(vg, x, y, w, h, startLine, visRows)
    end

    local drawY = y + PADDING_Y
    if self._scrollOffset > 0 then
        for hi = startHistRow, histLen do
            if drawY > y + h - 20 then break end
            self:_drawRow(vg, x + PADDING_X, drawY, self._buf.history[hi])
            drawY = drawY + LINE_HEIGHT
        end
    end

    for r = startScreenRow, self._rows do
        if drawY > y + h - 20 then break end
        local row = self._buf.screen[r]
        if row then
            self:_drawRow(vg, x + PADDING_X, drawY, row)
        end
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

    self:_drawStatusBar(vg, x, y + h - 20, w, 20)

    if self._overlayKeyboardVisible then
        self:_drawKeyboardOverlay(vg, x, y, w, h)
    end

    if self._scrollOffset > 0 then
        self:_drawScrollIndicator(vg, x + w - 8, y, 6, h - 20)
    end
end

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
            local bg = attr.bg
            if bg.r ~= BG_R or bg.g ~= BG_G or bg.b ~= BG_B then
                nvgBeginPath(vg)
                nvgRect(vg, cx, y, cw, LINE_HEIGHT)
                nvgFillColor(vg, nvgRGBA(bg.r, bg.g, bg.b, 255))
                nvgFill(vg)
            end

            if ch ~= " " and not attr.invisible then
                local fg = attr.reverse and attr.bg or attr.fg
                nvgFillColor(vg, nvgRGBA(fg.r, fg.g, fg.b, fg.a or 255))
                if attr.bold then
                    nvgFontBlur(vg, 0)
                    nvgText(vg, cx + 0.5, y, ch)
                end
                nvgText(vg, cx, y, ch)
            end

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

function TerminalView:_sendInput(data)
    if self._ssh and self._ssh.send then
        print("[TerminalView] Sending input: '" .. data:gsub("\r", "\\r"):gsub("\n", "\\n") .. "' (" .. #data .. " bytes)")
        local ok = self._ssh:send(data)
        if not ok then
            _trace("[TerminalView] send() returned false")
        end
    end
    self._scrollOffset = 0
end

function TerminalView:_invalidate()
    if self._view then
        self._view:invalidate()
    end
end

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

function TerminalView:_onPointerDown(event)
    local localEventX, localEventY = self:_toLocalPoint(event.x, event.y)

    if self._overlayKeyboardVisible then
        return true
    end

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
    
    if self._selection.startRow == self._selection.endRow and 
       math.abs(self._selection.startCol - self._selection.endCol) < 2 then
        self._selection = nil
    else
        local text = self:getSelectedText()
        if text and #text > 0 then
            brls.Application.getPlatform():setClipboard(text)
            self:setStatus("å·²å¤åˆ¶åˆ°å‰ªè´´æ¿", 100, 255, 100)
            brls.get_timer():once(1500, function()
                self:setStatus(self._ssh:isConnected() and "å·²è¿žæŽ¥" or "æœªè¿žæŽ¥")
            end)
        end
    end
    
    self:_invalidate()
    return true
end

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
