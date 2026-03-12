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
local PinyinIme     = require("pinyin_ime")
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

local TERMINAL_DEBUG = false
local function _debug(msg)
    if TERMINAL_DEBUG then
        _trace(msg)
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
local OVERLAY_RUMBLE_LOW = 300 -- ms, 震动持续时间
local OVERLAY_RUMBLE_HIGH = 200 -- 震动强度
local OVERLAY_RUMBLE_INTERVAL_MS = 1 -- 按键延迟
local OVERLAY_RUMBLE_PULSE_MS = 28 -- ms, 震动脉冲持续时间

local function _key(label, opts)
    opts = opts or {}
    opts.label = label
    opts.width = opts.width or 1
    return opts
end

-- ???????
-- 1) mech_rgb    ???????????
-- 2) gmk_rgb     GMK ??????
-- 3) light_mod   ???? + ?????
-- ??????????????????????
local OVERLAY_THEMES = {
    {
        key = "mech_rgb",
        name = "MECH",
        panel_fill = { 44, 48, 56 },
        panel_border = { 96, 104, 120 },
        panel_shadow = { 10, 12, 18 },
        title_text = { 240, 244, 250 },
        hint_text = { 186, 194, 208 },
        mode_text = { 255, 198, 92 },
        key_text = { 245, 247, 250 },
        key_text_active = { 255, 255, 255 },
        row_colors = {
            { 96, 123, 248 },
            { 66, 192, 170 },
            { 255, 172, 76 },
            { 186, 102, 255 },
            { 255, 104, 146 },
        },
        rainbow_key_colors = {
            { 255, 92, 92 },
            { 255, 136, 74 },
            { 255, 188, 74 },
            { 218, 220, 78 },
            { 132, 214, 90 },
            { 74, 208, 160 },
            { 68, 186, 255 },
            { 92, 144, 255 },
            { 132, 116, 255 },
            { 188, 108, 255 },
            { 255, 104, 200 },
            { 255, 114, 154 },
        },
        special = {
            enter = { 78, 206, 120 },
            backspace = { 234, 92, 92 },
            shift_caps = { 178, 110, 255 },
            ctrl_alt = { 76, 156, 255 },
            system = { 110, 120, 146 },
            tab = { 58, 178, 156 },
            space = { 244, 188, 72 },
            arrows = { 84, 94, 116 },
            symbol = { 255, 136, 84 },
        },
        state = {
            fill_lift = 10,
            top_lift = 24,
            border_lift = 18,
            selected_border = { 255, 238, 168 },
            active_border = { 255, 255, 255 },
            selected_fill_lift = 8,
            active_fill_lift = 14,
        },
        chip_colors = {
            { 96, 123, 248 },
            { 66, 192, 170 },
            { 255, 172, 76 },
            { 186, 102, 255 },
            { 255, 104, 146 },
        },
    },
    {
        key = "gmk_rgb",
        name = "GMK",
        panel_fill = { 34, 36, 42 },
        panel_border = { 80, 84, 96 },
        panel_shadow = { 8, 10, 14 },
        title_text = { 245, 244, 240 },
        hint_text = { 188, 190, 197 },
        mode_text = { 255, 205, 104 },
        key_text = { 246, 243, 236 },
        key_text_active = { 255, 255, 255 },
        row_colors = {
            { 232, 86, 83 },
            { 255, 190, 61 },
            { 77, 185, 124 },
            { 70, 141, 255 },
            { 180, 113, 255 },
        },
        special = {
            enter = { 63, 170, 120 },
            backspace = { 214, 78, 90 },
            shift_caps = { 150, 98, 230 },
            ctrl_alt = { 67, 126, 228 },
            system = { 108, 112, 126 },
            tab = { 62, 150, 120 },
            space = { 214, 160, 63 },
            arrows = { 90, 95, 112 },
            symbol = { 226, 118, 68 },
        },
        state = {
            fill_lift = 8,
            top_lift = 18,
            border_lift = 14,
            selected_border = { 255, 242, 180 },
            active_border = { 255, 255, 255 },
            selected_fill_lift = 6,
            active_fill_lift = 12,
        },
        chip_colors = {
            { 232, 86, 83 },
            { 255, 190, 61 },
            { 77, 185, 124 },
            { 70, 141, 255 },
            { 180, 113, 255 },
        },
    },
    {
        key = "light_mod",
        name = "LIGHT",
        panel_fill = { 238, 240, 244 },
        panel_border = { 186, 193, 206 },
        panel_shadow = { 110, 120, 138 },
        title_text = { 60, 68, 82 },
        hint_text = { 110, 118, 132 },
        mode_text = { 86, 126, 224 },
        key_text = { 58, 64, 76 },
        key_text_active = { 34, 38, 46 },
        row_colors = {
            { 230, 232, 236 },
            { 230, 232, 236 },
            { 230, 232, 236 },
            { 230, 232, 236 },
            { 230, 232, 236 },
        },
        special = {
            enter = { 107, 195, 130 },
            backspace = { 232, 112, 122 },
            shift_caps = { 181, 136, 255 },
            ctrl_alt = { 106, 164, 255 },
            system = { 255, 181, 96 },
            tab = { 104, 200, 176 },
            space = { 114, 178, 255 },
            arrows = { 168, 174, 188 },
            symbol = { 255, 164, 118 },
        },
        state = {
            fill_lift = 6,
            top_lift = 16,
            border_lift = 12,
            selected_border = { 112, 168, 255 },
            active_border = { 84, 128, 235 },
            selected_fill_lift = 4,
            active_fill_lift = 8,
        },
        chip_colors = {
            { 106, 164, 255 },
            { 104, 200, 176 },
            { 255, 181, 96 },
            { 181, 136, 255 },
            { 232, 112, 122 },
        },
    },
}

local OVERLAY_THEME_INDEX_DEFAULT = 1
local OVERLAY_THEME = OVERLAY_THEMES[OVERLAY_THEME_INDEX_DEFAULT]
local function _withAlpha(color, alpha)
    return nvgRGBA(color[1], color[2], color[3], alpha or 255)
end

local function _getOverlayLogicalRect(x, y, w, h)
    local okScale, windowScale = pcall(function()
        return brls.Application.getWindowScale and brls.Application.getWindowScale() or 1
    end)
    local okWindowW, windowW = pcall(function()
        return brls.Application.windowWidth and brls.Application.windowWidth() or w
    end)
    local okWindowH, windowH = pcall(function()
        return brls.Application.windowHeight and brls.Application.windowHeight() or h
    end)

    if not okScale or not okWindowW or not okWindowH then
        return x, y, w, h, 1, 1
    end

    if not windowScale or windowScale <= 0 then
        return x, y, w, h, 1, 1
    end

    local contentW = windowW / windowScale
    local contentH = windowH / windowScale
    if contentW <= 0 or contentH <= 0 then
        return x, y, w, h, 1, 1
    end

    local scaleX = w / contentW
    local scaleY = h / contentH
    if scaleX < 1.25 or scaleY < 1.25 then
        return x, y, w, h, 1, 1
    end

    return x / scaleX, y / scaleY, contentW, contentH, scaleX, scaleY
end

local function _liftColor(color, amount)
    return {
        math.min(255, color[1] + amount),
        math.min(255, color[2] + amount),
        math.min(255, color[3] + amount),
    }
end

local function _pickThemeKeyColor(theme, key, rowIndex)
    if not theme.rainbow_key_colors or #theme.rainbow_key_colors == 0 then
        return theme.row_colors[rowIndex] or theme.row_colors[#theme.row_colors]
    end

    local token = tostring((key and key.label) or '') .. ':' .. tostring((key and key.action) or '')
    local hash = 0
    for i = 1, #token do
        hash = (hash + string.byte(token, i) * (i + 3)) % 9973
    end

    local index = (hash % #theme.rainbow_key_colors) + 1
    return theme.rainbow_key_colors[index]
end

local function _overlayKeyPalette(key, rowIndex, selected, active)
    local theme = OVERLAY_THEME
    local base = _pickThemeKeyColor(theme, key, rowIndex)

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

local OVERLAY_LAYOUT_CLASSIC = {
    {
        _key("Esc", { action = "send", value = Platform.keyMap.ESC, width = 1.25 }),
        _key("1", { action = "char", base = "1", shift = "!", fnLabel = "F1", fnAction = "send", fnValue = Platform.keyMap.F1 }),
        _key("2", { action = "char", base = "2", shift = "@", fnLabel = "F2", fnAction = "send", fnValue = Platform.keyMap.F2 }),
        _key("3", { action = "char", base = "3", shift = "#", fnLabel = "F3", fnAction = "send", fnValue = Platform.keyMap.F3 }),
        _key("4", { action = "char", base = "4", shift = "$", fnLabel = "F4", fnAction = "send", fnValue = Platform.keyMap.F4 }),
        _key("5", { action = "char", base = "5", shift = "%", fnLabel = "F5", fnAction = "send", fnValue = Platform.keyMap.F5 }),
        _key("6", { action = "char", base = "6", shift = "^", fnLabel = "F6", fnAction = "send", fnValue = Platform.keyMap.F6 }),
        _key("7", { action = "char", base = "7", shift = "&", fnLabel = "F7", fnAction = "send", fnValue = Platform.keyMap.F7 }),
        _key("8", { action = "char", base = "8", shift = "*", fnLabel = "F8", fnAction = "send", fnValue = Platform.keyMap.F8 }),
        _key("9", { action = "char", base = "9", shift = "(", fnLabel = "F9", fnAction = "send", fnValue = Platform.keyMap.F9 }),
        _key("0", { action = "char", base = "0", shift = ")", fnLabel = "F10", fnAction = "send", fnValue = Platform.keyMap.F10 }),
        _key("-", { action = "char", base = "-", shift = "_", fnLabel = "F11", fnAction = "send", fnValue = Platform.keyMap.F11 }),
        _key("=", { action = "char", base = "=", shift = "+", fnLabel = "F12", fnAction = "send", fnValue = Platform.keyMap.F12 }),
        _key("BS", { action = "backspace", width = 1.75, fnLabel = "Del", fnAction = "send", fnValue = Platform.keyMap.DEL }),
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
        _key(ARROW_UP_LABEL, { action = "send", value = Platform.keyMap.UP, width = 1.15, fnLabel = "PgUp", fnValue = Platform.keyMap.PGUP }),
        _key("`", { action = "char", base = "~", shift = "`", width = 1.15 }),
    },
    {
        _key("中/EN", { action = "cn", width = 1.15 }),
        _key("Ctrl", { action = "ctrl", width = 1.15 }),
        _key("Win", { action = "meta", width = 1.15 }),
        _key("Alt", { action = "alt", width = 1.15 }),
        _key("Space", { action = "space", width = 5.5 }),
        _key("Fn", { action = "fn", width = 1.15 }),
        
        _key(ARROW_LEFT_LABEL, { action = "send", value = Platform.keyMap.LEFT, width = 1.15, fnLabel = "Home", fnValue = Platform.keyMap.HOME }),
        _key(ARROW_DOWN_LABEL, { action = "send", value = Platform.keyMap.DOWN, width = 1.15, fnLabel = "PgDn", fnValue = Platform.keyMap.PGDN }),
        _key(ARROW_RIGHT_LABEL, { action = "send", value = Platform.keyMap.RIGHT, width = 1.15, fnLabel = "End", fnValue = Platform.keyMap.END }),
    },
}

local OVERLAY_LAYOUT_COMPACT = {
    {
        _key("Esc", { action = "send", value = Platform.keyMap.ESC, width = 1 }),
        _key("Tab", { action = "tab", width = 1 }),
        _key("Caps", { action = "caps", width = 0.75}),
        _key("`", { action = "char", base = "~", shift = "`", width = 0.75 }),
        _key("[", { action = "char", base = "[", width = 0.75, shift = "{"  }),
        _key("]", { action = "char", base = "]", width = 0.75, shift = "}" }),
        _key("-", { action = "char", base = "-", width = 0.75, shift = "_" }),
        _key("=", { action = "char", base = "=", width = 0.75, shift = "+" }),
        _key("BS", { action = "backspace", width = 1.5, fnLabel = "Del", fnAction = "send", fnValue = Platform.keyMap.DEL }),
        _key("Enter", { action = "enter", width = 2 }),
    },  
    {
        _key("q", { action = "char", base = "q", letter = true, width = 1, slot = "q", fnLabel = "F1", fnAction = "send", fnValue = Platform.keyMap.F1 }),
        _key("w", { action = "char", base = "w", letter = true, width = 1, slot = "w", fnLabel = "F2", fnAction = "send", fnValue = Platform.keyMap.F2 }),
        _key("e", { action = "char", base = "e", letter = true, width = 1, slot = "e", fnLabel = "F3", fnAction = "send", fnValue = Platform.keyMap.F3 }),
        _key("r", { action = "char", base = "r", letter = true, width = 1, slot = "r", fnLabel = "F4", fnAction = "send", fnValue = Platform.keyMap.F4 }),
        _key("t", { action = "char", base = "t", letter = true, width = 1, slot = "t", fnLabel = "F5", fnAction = "send", fnValue = Platform.keyMap.F5 }),
        _key("y", { action = "char", base = "y", letter = true, width = 1, slot = "y", fnLabel = "F6", fnAction = "send", fnValue = Platform.keyMap.F6 }),
        _key("u", { action = "char", base = "u", letter = true, width = 1, slot = "u", fnLabel = "F7", fnAction = "send", fnValue = Platform.keyMap.F7 }),
        _key("i", { action = "char", base = "i", letter = true, width = 1, slot = "i", fnLabel = ARROW_UP_LABEL, fnAction = "send", fnValue = Platform.keyMap.UP }),
        _key("o", { action = "char", base = "o", letter = true, width = 1, slot = "o" }),
        _key("p", { action = "char", base = "p", letter = true, width = 1, slot = "p" }),
    },  
    {
        _key(" ", { action = "", width = 0.25}),
        _key("a", { action = "char", base = "a", letter = true, width = 1, slot = "a", fnLabel = "F8", fnAction = "send", fnValue = Platform.keyMap.F8 }),
        _key("s", { action = "char", base = "s", letter = true, width = 1, slot = "s", fnLabel = "F9", fnAction = "send", fnValue = Platform.keyMap.F9 }),
        _key("d", { action = "char", base = "d", letter = true, width = 1, slot = "d", fnLabel = "F10", fnAction = "send", fnValue = Platform.keyMap.F10 }),
        _key("f", { action = "char", base = "f", letter = true, width = 1, slot = "f", fnLabel = "F11", fnAction = "send", fnValue = Platform.keyMap.F11 }),
        _key("g", { action = "char", base = "g", letter = true, width = 1, slot = "g", fnLabel = "F12", fnAction = "send", fnValue = Platform.keyMap.F12 }),
        _key("h", { action = "char", base = "h", letter = true, width = 1, slot = "h" }),
        _key("j", { action = "char", base = "j", letter = true, width = 1, slot = "j", fnLabel = ARROW_LEFT_LABEL, fnAction = "send", fnValue = Platform.keyMap.LEFT }),
        _key("k", { action = "char", base = "k", letter = true, width = 1, slot = "k", fnLabel = ARROW_DOWN_LABEL, fnAction = "send", fnValue = Platform.keyMap.DOWN }),
        _key("l", { action = "char", base = "l", letter = true, width = 1, slot = "l", fnLabel = ARROW_RIGHT_LABEL, fnAction = "send", fnValue = Platform.keyMap.RIGHT }),
        _key(";", { action = "char", base = ";", shift = ":", width = 0.75 }),
    },
    {
        _key("Shift", { action = "shift", width = 0.75}),
        _key("z", { action = "char", base = "z", letter = true, width = 1, slot = "z", fnLabel = "1", fnAction = "char", fnBase = "1", fnShift = "!" }),
        _key("x", { action = "char", base = "x", letter = true, width = 1, slot = "x", fnLabel = "2", fnAction = "char", fnBase = "2", fnShift = "@" }),
        _key("c", { action = "char", base = "c", letter = true, width = 1, slot = "c", fnLabel = "3", fnAction = "char", fnBase = "3", fnShift = "#" }),
        _key("v", { action = "char", base = "v", letter = true, width = 1, slot = "v", fnLabel = "4", fnAction = "char", fnBase = "4", fnShift = "$" }),
        _key("b", { action = "char", base = "b", letter = true, width = 1, slot = "b", fnLabel = "5", fnAction = "char", fnBase = "5", fnShift = "%" }),
        _key("n", { action = "char", base = "n", letter = true, width = 1, slot = "n", fnLabel = "6", fnAction = "char", fnBase = "6", fnShift = "^" }),
        _key("m", { action = "char", base = "m", letter = true, width = 1, slot = "m", fnLabel = "7", fnAction = "char", fnBase = "7", fnShift = "&" }),
        _key(",", { action = "char", base = ",", shift = "<", width = 0.75, fnLabel = "8", fnAction = "char", fnBase = "8", fnShift = "*" }),
        _key(".", { action = "char", base = ".", shift = ">", width = 0.75, fnLabel = "9", fnAction = "char", fnBase = "9", fnShift = "(" }),
        _key("/", { action = "char", base = "/", shift = "?", width = 0.75, fnLabel = "0", fnAction = "char", fnBase = "0", fnShift = ")" }),
    },
    {
        _key("Ctrl", { action = "ctrl", width = 1 }),
        _key("Win", { action = "meta", width = 1}),
        _key("Alt", { action = "alt", width = 1}),
        _key("Space", { action = "space", width = 4 }),
        _key("\228\184\173/EN", { action = "cn", width = 0.75 }),
        _key("Fn", { action = "fn", width = 0.75 }),
        _key("\\", { action = "char", base = "\\", shift = "|", width = 0.75 }),
        _key("'", { action = "char", base = "'", shift = '"', width = 0.75 }),
    },
}

local OVERLAY_COMPACT_FN_PAGES = {
    {
        name = "NUM",
        normal = {
            q = { label = "F1", action = "send", value = Platform.keyMap.F1 },
            w = { label = "F2", action = "send", value = Platform.keyMap.F2 },
            e = { label = "F3", action = "send", value = Platform.keyMap.F3 },
            r = { label = "F4", action = "send", value = Platform.keyMap.F4 },
            t = { label = "F5", action = "send", value = Platform.keyMap.F5 },
            y = { label = "F6", action = "send", value = Platform.keyMap.F6 },
            u = { label = "F7", action = "send", value = Platform.keyMap.F7 },
            i = { label = ARROW_UP_LABEL, action = "send", value = Platform.keyMap.UP },
            a = { label = "F8", action = "send", value = Platform.keyMap.F8 },
            s = { label = "F9", action = "send", value = Platform.keyMap.F9 },
            d = { label = "F10", action = "send", value = Platform.keyMap.F10 },
            f = { label = "F11", action = "send", value = Platform.keyMap.F11 },
            g = { label = "F12", action = "send", value = Platform.keyMap.F12 },
            j = { label = ARROW_LEFT_LABEL, action = "send", value = Platform.keyMap.LEFT },
            k = { label = ARROW_DOWN_LABEL, action = "send", value = Platform.keyMap.DOWN },
            l = { label = ARROW_RIGHT_LABEL, action = "send", value = Platform.keyMap.RIGHT },
            z = { label = "1", action = "char", base = "1", shift = "!" },
            x = { label = "2", action = "char", base = "2", shift = "@" },
            c = { label = "3", action = "char", base = "3", shift = "#" },
            v = { label = "4", action = "char", base = "4", shift = "$" },
            b = { label = "5", action = "char", base = "5", shift = "%" },
            n = { label = "6", action = "char", base = "6", shift = "^" },
            m = { label = "7", action = "char", base = "7", shift = "&" },
        },
    },
}

local function _getOverlayLayoutByMode(mode)
    if mode == "compact" then
        return OVERLAY_LAYOUT_COMPACT
    end
    return OVERLAY_LAYOUT_CLASSIC
end

local function _getDefaultOverlayKeyByMode(mode)
    local layout = _getOverlayLayoutByMode(mode)
    if mode == "compact" then
        return layout[1][1]
    end
    return layout[2][2]
end

local function _resolveOverlayVariant(baseKey, variant)
    return {
        label = variant.label or baseKey.label,
        action = variant.action or baseKey.action,
        value = variant.value,
        base = variant.base,
        shift = variant.shift,
        letter = variant.letter,
        width = variant.width or baseKey.width,
        slot = baseKey.slot,
    }
end

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

    self._statusText     = "未连接"
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
    self._overlayFn = false
    self._overlayMeta = false
    self._overlayCn = false
    self._overlayLayoutMode = "classic"
    self._overlayFnPage = 1
    self._overlayPinyin = ""
    self._overlayImeCandidates = {}
    self._overlayImePage = 1
    self._overlayImeLastCommit = nil
    self._overlayTouchTargets = {}
    self._overlayPanelRect = nil
    self._overlaySelectedKey = _getDefaultOverlayKeyByMode(self._overlayLayoutMode)
    self._overlayRecentCommands = {}
    self._overlayThemeIndex = OVERLAY_THEME_INDEX_DEFAULT
    OVERLAY_THEME = OVERLAY_THEMES[self._overlayThemeIndex]
    self._drawX = 0
    self._drawY = 0
    self._drawW = 0
    self._drawH = 0
    self._buttonRepeatState = {}
    self._touchState = { pressed = false, x = 0, y = 0, id = -1 }
    self._lastOverlayRumbleAt = 0
    self._overlayRumbleSeq = 0
    self._overlayRumbleCooling = false
    self._frameLoopActive = false
    self._overlayShortcutLatch = false

    return self
end

function TerminalView:_startFrameLoop()
    if self._frameLoopActive then
        return
    end

    self._frameLoopActive = true

    local function tick()
        if not self._frameLoopActive or not self._view then
            return
        end

        self:_onFrame(16)
        brls.delay(16, tick)
    end

    brls.delay(16, tick)
end

function TerminalView:bindView(view)
    local okInit, initResult = pcall(initGlobalKeyboardListeners)
    _debug("[TerminalView] bindView input init: ok=" .. tostring(okInit) .. " result=" .. tostring(initResult))
    self._view = view
    if view then
        _G.__SSH_ACTIVE_TERMINAL = self
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
            end)
            view:registerAction("Delete", brls.ControllerButton.BUTTON_B, function()
                self:_sendInput(Platform.keyMap.BS)
                return true
            end)
            view:registerAction("Ctrl+C", brls.ControllerButton.BUTTON_X, function()
                self:_sendInput(Platform.keyMap.CTRL_C)
                return true
            end)
            view:registerAction("EOF", brls.ControllerButton.BUTTON_Y, function()
                self:_sendInput(Platform.keyMap.CTRL_D)
                return true
            end)
            view:registerAction("Tab", brls.ControllerButton.BUTTON_LB, function()
                self:_sendInput(Platform.keyMap.TAB)
                return true
            end)
            view:registerAction("System IME", brls.ControllerButton.BUTTON_START, function()
                self:_openSystemIme()
                return true
            end)
            view:registerAction("Close", brls.ControllerButton.BUTTON_BACK, function()
                if self._onCloseRequest then
                    self._onCloseRequest()
                elseif self._ssh:isConnected() then
                    self._ssh:disconnect()
                end
                return true
            end)
        end
        _G.__SSH_TERMINALS = _G.__SSH_TERMINALS or {}
        local addr = tostring(view:get_address())
        _G.__SSH_TERMINALS[addr] = self
        _debug("[TerminalView] Registered mapping for address: " .. addr)

        local curr = view:getParent()
        while curr do
            local paddr = tostring(curr:get_address())
            _G.__SSH_TERMINALS[paddr] = self
            _debug("[TerminalView] Registered mapping for parent/ancestor address: " .. paddr)
            curr = curr:getParent()
        end

        if view.registerFrameCallback then
            view:registerFrameCallback(function(dt)
                self:_onFrame(dt)
            end)
        else
            self:_startFrameLoop()
        end

        if view.onWillDisappear then
            view:onWillDisappear(function()
                self._frameLoopActive = false
                if _G.__SSH_ACTIVE_TERMINAL == self then
                    _G.__SSH_ACTIVE_TERMINAL = nil
                end
                if _G.__SSH_TERMINALS then
                    _G.__SSH_TERMINALS[view:get_address()] = nil
                end
            end)
        end

        if view.onFocusGained then
            view:onFocusGained(function()
                _G.__SSH_ACTIVE_TERMINAL = self
            end)
        end

        view:onPointerDown(function(event)
            _G.__SSH_ACTIVE_TERMINAL = self
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
    if not inputManager then
        _debug("[TerminalView] initGlobalKeyboardListeners: no input manager")
        return false
    end
    if not inputManager.getCharInputEvent or not inputManager.getKeyboardKeyStateChanged then
        _debug("[TerminalView] initGlobalKeyboardListeners: keyboard APIs unavailable")
        return false
    end
    local KEY_K = 75
    local KEY_K_LOWER = 107
    local KEY_F2 = 291

    local function hasFlag(value, flag)
        if not value or not flag or flag <= 0 then
            return false
        end
        return (value % (flag * 2)) >= flag
    end

    local function isCtrlPressed(mods)
        return hasFlag(mods, 0x02) or hasFlag(mods, 0x40) or hasFlag(mods, 0x80)
    end

    local function isMetaPressed(mods)
        return hasFlag(mods, 0x08)
    end

    local function isPrimaryShortcutPressed(mods)
        return isCtrlPressed(mods) or isMetaPressed(mods)
    end
    
    if _G.__SSH_TERMINAL_INPUT_INITED then
        _debug("[TerminalView] initGlobalKeyboardListeners: already initialized")
        return true
    end
    _G.__SSH_TERMINAL_INPUT_INITED = true
    _debug("[TerminalView] initGlobalKeyboardListeners: registering listeners")

    local function resolveTerminalFromFocus()
        local focus = brls.Application.getCurrentFocus()
        if focus and _G.__SSH_TERMINALS then
            local curr = focus
            while curr do
                local addr = tostring(curr:get_address())
                local terminal = _G.__SSH_TERMINALS[addr]
                if terminal then
                    return terminal
                end
                curr = curr:getParent()
            end
        end

        return _G.__SSH_ACTIVE_TERMINAL
    end

    inputManager:getCharInputEvent():subscribe(function(codepoint)
        local terminal = resolveTerminalFromFocus()
        if terminal then
            _debug("[TerminalView] Character input: " .. tostring(codepoint))
            if codepoint == 11 then -- Ctrl+K
                terminal:_toggleOverlayKeyboardVisible()
                return
            end
            if terminal._overlayKeyboardVisible and terminal._overlayCn and (not terminal._overlayFn) then
                if codepoint >= 65 and codepoint <= 90 then
                    terminal:_appendOverlayIme(string.lower(string.char(codepoint)))
                    return
                elseif codepoint >= 97 and codepoint <= 122 then
                    terminal:_appendOverlayIme(string.char(codepoint))
                    return
                elseif codepoint >= 49 and codepoint <= 56 and #(terminal._overlayPinyin or "") > 0 then
                    terminal:_commitOverlayIme(codepoint - 48, false)
                    return
                elseif codepoint == 32 and #(terminal._overlayPinyin or "") > 0 then
                    terminal:_commitOverlayIme(1, true)
                    return
                end
            end
            terminal._keyboard:handleChar(codepoint)
        end
    end)

    inputManager:getKeyboardKeyStateChanged():subscribe(function(state)
        local terminal = resolveTerminalFromFocus()
        if terminal and not state.pressed then
            if state.key == KEY_K or state.key == KEY_K_LOWER or state.key == KEY_F2 or state.key == 341 or state.key == 343 then
                terminal:_releaseOverlayShortcutLatch()
            end
            return
        end

        if state.pressed then
            local focus = brls.Application.getCurrentFocus()
            _debug(string.format("[TerminalView] Global Key: key=%d mods=%d focus=%s",
                state.key, state.mods, focus and tostring(focus:get_address()) or "nil"))

            if terminal then
                local shortcut = isPrimaryShortcutPressed(state.mods)
                if (shortcut and (state.key == KEY_K or state.key == KEY_K_LOWER)) or state.key == KEY_F2 then
                    terminal:_toggleOverlayKeyboardVisible()
                    return
                end

                if terminal._overlayKeyboardVisible and terminal._overlayCn and (not terminal._overlayFn) and #(terminal._overlayPinyin or "") > 0 then
                    if state.key == 257 then
                        terminal:_commitOverlayIme(1, true)
                        return
                    elseif state.key == 259 then
                        if terminal:_backspaceOverlayIme() then
                            return
                        end
                    elseif state.key == 266 then
                        if terminal:_changeOverlayImePage(-1) then
                            return
                        end
                    elseif state.key == 267 then
                        if terminal:_changeOverlayImePage(1) then
                            return
                        end
                    end
                end

                terminal._keyboard:handleKey(state.key, state.mods)
            end
        end
    end)

    return true
end

function TerminalView:feedData(data)
    if not data or #data == 0 then return end
    _debug("[TerminalView] feedData: " .. #data .. " bytes")
    local ops = self._parser:feed(data)
    for _, op in ipairs(ops) do
        if op.type == "dsr_report" then
            local resp = string.format("\27[%d;%dR", self._buf.curRow, self._buf.curCol)
            _debug("[TerminalView] Responding to DSR with: " .. resp)
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
    self._statusText = "未连接"
    self._statusColor = { r = 150, g = 150, b = 150 }
    self._overlayKeyboardVisible = false
    self._overlayBuffer = ""
    self._overlayShift = false
    self._overlayCaps = false
    self._overlayCtrl = false
    self._overlayAlt = false
    self._overlayFn = false
    self._overlayMeta = false
    self._overlayCn = false
    self._overlayLayoutMode = self._overlayLayoutMode or "classic"
    self._overlayFnPage = 1
    self._overlayPinyin = ""
    self._overlayImeCandidates = {}
    self._overlayImePage = 1
    self._overlayImeLastCommit = nil
    self._overlayTouchTargets = {}
    self._overlayPanelRect = nil
    self._overlaySelectedKey = _getDefaultOverlayKeyByMode(self._overlayLayoutMode)
    self._overlayRecentCommands = {}
    self._overlayThemeIndex = self._overlayThemeIndex or OVERLAY_THEME_INDEX_DEFAULT
    OVERLAY_THEME = OVERLAY_THEMES[self._overlayThemeIndex]
    self._buttonRepeatState = {}
    self._touchState = { pressed = false, x = 0, y = 0, id = -1 }
    self._overlayRumbleCooling = false
    self._overlayRumbleSeq = 0
    self:_invalidate()
end

function TerminalView:setOnCloseRequest(callback)
    self._onCloseRequest = callback
end

function TerminalView:setOverlayKeyboardVisible(visible)
    self._overlayKeyboardVisible = visible and true or false
    self._overlayShortcutLatch = false
    self:_invalidate()
end

function TerminalView:_toggleOverlayKeyboardVisible()
    if self._overlayShortcutLatch then
        return
    end

    self._overlayShortcutLatch = true
    self._overlayKeyboardVisible = not self._overlayKeyboardVisible
    print("[TerminalView] Overlay keyboard visible = " .. tostring(self._overlayKeyboardVisible))
    self:_invalidate()
end

function TerminalView:_releaseOverlayShortcutLatch()
    self._overlayShortcutLatch = false
end

function TerminalView:ensureInputListeners()
    local okInit, initResult = pcall(initGlobalKeyboardListeners)
    _debug("[TerminalView] ensureInputListeners: ok=" .. tostring(okInit) .. " result=" .. tostring(initResult))
end

local function _overlayTrim(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function TerminalView:_refreshOverlayImeCandidates()
    if self._overlayCn and not self._overlayFn and #self._overlayPinyin > 0 then
        self._overlayImeCandidates = PinyinIme.getCandidates(self._overlayPinyin, {
            limit = 48,
            prev_text = self._overlayImeLastCommit,
        })
    else
        self._overlayImeCandidates = {}
    end

    local pageCount = self:_getOverlayImePageCount()
    if self._overlayImePage > pageCount then
        self._overlayImePage = pageCount
    end
    if self._overlayImePage < 1 then
        self._overlayImePage = 1
    end
end

function TerminalView:_clearOverlayIme()
    self._overlayPinyin = ""
    self._overlayImeCandidates = {}
    self._overlayImePage = 1
end

function TerminalView:_appendOverlayIme(char)
    if not char or char == "" then return end
    self._overlayPinyin = string.lower((self._overlayPinyin or "") .. char)
    self._overlayImePage = 1
    self:_refreshOverlayImeCandidates()
    self:_invalidate()
end

function TerminalView:_backspaceOverlayIme()
    if #self._overlayPinyin <= 0 then
        return false
    end
    self._overlayPinyin = string.sub(self._overlayPinyin, 1, #self._overlayPinyin - 1)
    self._overlayImePage = 1
    self:_refreshOverlayImeCandidates()
    self:_invalidate()
    return true
end

function TerminalView:_getOverlayImePageCount()
    local pageSize = PinyinIme.PAGE_SIZE or 8
    local count = #self._overlayImeCandidates
    return math.max(1, math.ceil(count / pageSize))
end

function TerminalView:_getOverlayImeVisibleCandidates()
    local pageSize = PinyinIme.PAGE_SIZE or 8
    local page = self._overlayImePage or 1
    local startIndex = (page - 1) * pageSize + 1
    local out = {}
    for index = startIndex, math.min(#self._overlayImeCandidates, startIndex + pageSize - 1) do
        table.insert(out, self._overlayImeCandidates[index])
    end
    return out
end

function TerminalView:_changeOverlayImePage(delta, source)
    local pageCount = self:_getOverlayImePageCount()
    if pageCount <= 1 then
        return false
    end
    local nextPage = math.max(1, math.min(pageCount, (self._overlayImePage or 1) + delta))
    if nextPage == self._overlayImePage then
        return false
    end
    self._overlayImePage = nextPage
    self:_rumbleOverlayTap("nav", source)
    self:_invalidate()
    return true
end

function TerminalView:_selectOverlayImeCandidate(candidate, fallbackToRaw)
    if not self._overlayCn or self._overlayFn then
        return false
    end

    local raw = self._overlayPinyin or ""
    if raw == "" then
        return false
    end

    local text = candidate and candidate.text or nil
    local remaining = candidate and candidate.remaining or ""
    if (not text or text == "") and fallbackToRaw then
        text = raw
        remaining = ""
    end
    if not text or text == "" then
        return false
    end

    self:_appendOverlayText(text)
    PinyinIme.rememberSelection(raw, text, self._overlayImeLastCommit)
    self._overlayImeLastCommit = text
    self._overlayPinyin = remaining or ""
    self._overlayImePage = 1
    self:_refreshOverlayImeCandidates()
    self:_invalidate()
    return true
end

function TerminalView:_commitOverlayIme(index, fallbackToRaw)
    if not self._overlayCn or self._overlayFn then
        return false
    end
    self:_refreshOverlayImeCandidates()
    local visible = self:_getOverlayImeVisibleCandidates()
    return self:_selectOverlayImeCandidate(visible[index or 1], fallbackToRaw)
end

function TerminalView:_flushOverlayIme(fallbackToRaw)
    if not self._overlayCn or self._overlayFn or #self._overlayPinyin == 0 then
        return false
    end
    return self:_commitOverlayIme(1, fallbackToRaw)
end

function TerminalView:_clearOverlayModifiers(clearCaps)
    self._overlayShift = false
    self._overlayCtrl = false
    self._overlayAlt = false
    self._overlayMeta = false
    if clearCaps then
        self._overlayCaps = false
    end
end

function TerminalView:_getOverlayLayout()
    return _getOverlayLayoutByMode(self._overlayLayoutMode)
end

function TerminalView:_isCompactOverlayLayout()
    return self._overlayLayoutMode == "compact"
end

function TerminalView:_toggleOverlayLayout()
    self._overlayLayoutMode = self:_isCompactOverlayLayout() and "classic" or "compact"
    self._overlayFn = false
    self._overlayMeta = false
    self._overlayFnPage = 1
    self._overlaySelectedKey = _getDefaultOverlayKeyByMode(self._overlayLayoutMode)
    self:_refreshOverlayImeCandidates()
    self:_invalidate()
end

function TerminalView:_cycleOverlayFnPage()
    local pageCount = #OVERLAY_COMPACT_FN_PAGES
    if pageCount <= 0 then
        return
    end

    if not self._overlayFn then
        self._overlayFn = true
        self._overlayFnPage = math.min(2, pageCount)
    else
        self._overlayFnPage = (self._overlayFnPage or 1) + 1
        if self._overlayFnPage > pageCount then
            self._overlayFnPage = 1
        end
    end

    self:_refreshOverlayImeCandidates()
    self:_invalidate()
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
    local preserveShiftLayer = self:_isCompactOverlayLayout() and self._overlayFn and self._overlayShift

    if self._overlayCtrl and #out == 1 then
        local byte = string.byte(string.upper(out))
        if byte and byte >= 65 and byte <= 90 then
            out = string.char(byte - 64)
        end
    end

    if self._overlayAlt then
        out = Platform.keyMap.ESC .. out
    end

    if not preserveShiftLayer then
        self._overlayShift = false
    end
    self._overlayCtrl = false
    self._overlayAlt = false
    self._overlayMeta = false
    return out
end

function TerminalView:_resolveOverlayKey(key)
    if not key then
        return key
    end

    if key.action == "cn" then
        return {
            label = self._overlayCn and "EN" or "\228\184\173",
            action = "cn",
            width = key.width,
        }
    end

    if self:_isCompactOverlayLayout() and self._overlayFn and key.slot then
        local page = OVERLAY_COMPACT_FN_PAGES[self._overlayFnPage or 1]
        local variants = page and ((self._overlayShift and page.shift) or page.normal)
        local variant = variants and variants[key.slot]
        if variant then
            return _resolveOverlayVariant(key, variant)
        end
    end

    if self._overlayFn and key.fnLabel then
        return {
            label = key.fnLabel,
            action = key.fnAction or key.action,
            value = key.fnValue,
            base = key.fnBase,
            shift = key.fnShift,
            letter = key.fnLetter,
            width = key.width,
        }
    end
    return key
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
    self._overlayMeta = false
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

function TerminalView:_activateOverlayKey(key, source)
    if not key then return end
    self._overlaySelectedKey = key
    self:_rumbleOverlayTap(nil, source)

    local resolved = self:_resolveOverlayKey(key)
    local composingCn = self._overlayCn and not self._overlayFn and #self._overlayPinyin > 0

    if self._overlayCn and not self._overlayFn and resolved.action == "char" and resolved.letter then
        self:_appendOverlayIme(string.lower(resolved.base or resolved.label or ""))
        return
    elseif composingCn and resolved.action == "char" and (resolved.base or ""):match("^%d$") then
        local idx = tonumber(resolved.base)
        if idx then
            self:_commitOverlayIme(idx, false)
        end
        return
    elseif composingCn and resolved.action == "backspace" then
        if self:_backspaceOverlayIme() then
            return
        end
    elseif composingCn and resolved.action == "space" then
        self:_commitOverlayIme(1, true)
        return
    elseif composingCn and resolved.action == "enter" then
        self:_commitOverlayIme(1, true)
        return
    elseif composingCn and (resolved.action == "text" or resolved.action == "send" or resolved.action == "tab" or (resolved.action == "char" and not resolved.letter)) then
        self:_flushOverlayIme(true)
    end

    if resolved.action == "char" then
        self:_appendOverlayText(self:_applyOverlayModifiers(self:_resolveOverlayChar(resolved)))
    elseif resolved.action == "text" then
        self:_appendOverlayText(self:_applyOverlayModifiers(resolved.value or resolved.label))
    elseif resolved.action == "space" then
        self:_appendOverlayText(self:_applyOverlayModifiers(" "))
    elseif resolved.action == "send" then
        self:_sendInput(self:_applyOverlayModifiers(resolved.value or ""))
        self:_invalidate()
    elseif resolved.action == "tab" then
        self:_sendInput(Platform.keyMap.TAB)
        self:_clearOverlayModifiers(false)
        self:_invalidate()
    elseif resolved.action == "enter" then
        self:_submitOverlayBuffer()
    elseif resolved.action == "backspace" then
        self:_backspaceOverlayBuffer()
    elseif resolved.action == "shift" then
        self._overlayShift = not self._overlayShift
        self:_invalidate()
    elseif resolved.action == "caps" then
        self._overlayCaps = not self._overlayCaps
        self:_invalidate()
    elseif resolved.action == "ctrl" then
        self._overlayCtrl = not self._overlayCtrl
        self:_invalidate()
    elseif resolved.action == "alt" then
        self._overlayAlt = not self._overlayAlt
        self:_invalidate()
    elseif resolved.action == "meta" then
        self:_toggleOverlayLayout()
    elseif resolved.action == "fn" then
        self._overlayFn = not self._overlayFn
        if not self._overlayFn then
            self._overlayFnPage = 1
            self:_refreshOverlayImeCandidates()
        end
        self:_invalidate()
    elseif resolved.action == "fn_page" then
        self:_cycleOverlayFnPage()
    elseif resolved.action == "cn" then
        if self._overlayCn and #self._overlayPinyin > 0 then
            self:_flushOverlayIme(true)
        end
        self._overlayCn = not self._overlayCn
        self:_refreshOverlayImeCandidates()
        self:_invalidate()
    end
end

function TerminalView:_cycleOverlayTheme()
    self._overlayThemeIndex = (self._overlayThemeIndex or OVERLAY_THEME_INDEX_DEFAULT) + 1
    if self._overlayThemeIndex > #OVERLAY_THEMES then
        self._overlayThemeIndex = 1
    end
    OVERLAY_THEME = OVERLAY_THEMES[self._overlayThemeIndex]
    self:_invalidate()
end

function TerminalView:_rumbleOverlayTap(kind, source)
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

    local sourceScale = 1.0
    if source == "joycon" then
        sourceScale = 0.2
    elseif source == "touch" then
        sourceScale = 2.0
    end

    low = math.max(0, math.min(65535, math.floor(low * sourceScale)))
    high = math.max(0, math.min(65535, math.floor(high * sourceScale)))

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

    if not (self._overlayCn and not self._overlayFn and #self._overlayPinyin > 0) then
        return items
    end

    self:_refreshOverlayImeCandidates()
    local page = self._overlayImePage or 1
    local pageCount = self:_getOverlayImePageCount()
    local visible = self:_getOverlayImeVisibleCandidates()

    if page > 1 then
        table.insert(items, { mode = "ime_prev", display = string.format("< %d/%d", page, pageCount) })
    end

    for index, candidate in ipairs(visible) do
        local suffix = (candidate.remaining and candidate.remaining ~= "") and "+" or ""
        table.insert(items, {
            text = candidate.text,
            mode = "ime",
            candidate = candidate,
            display = string.format("%d.%s%s", index, candidate.text, suffix),
        })
    end

    if page < pageCount then
        table.insert(items, { mode = "ime_next", display = string.format("%d/%d >", page, pageCount) })
    end

    return items
end

function TerminalView:_applySuggestion(item, source)
    if not item then return end
    self:_rumbleOverlayTap(nil, source)
    if item.mode == "ime" then
        self:_selectOverlayImeCandidate(item.candidate or { text = item.text }, true)
    elseif item.mode == "ime_prev" then
        self:_changeOverlayImePage(-1, source)
    elseif item.mode == "ime_next" then
        self:_changeOverlayImePage(1, source)
    elseif item.mode == "replace" then
        self:_syncOverlayBuffer(item.text)
    else
        self:_appendOverlayText(item.text)
    end
end

function TerminalView:_findOverlayKeyPosition(target)
    local layout = self:_getOverlayLayout()
    if not target then
        local defaultKey = _getDefaultOverlayKeyByMode(self._overlayLayoutMode)
        return self:_findOverlayKeyPosition(defaultKey)
    end

    for rowIndex, row in ipairs(layout) do
        for colIndex, key in ipairs(row) do
            if key == target then
                return rowIndex, colIndex
            end
        end
    end

    local fallbackKey = _getDefaultOverlayKeyByMode(self._overlayLayoutMode)
    if target ~= fallbackKey then
        return self:_findOverlayKeyPosition(fallbackKey)
    end

    return 1, 1
end

function TerminalView:_moveOverlaySelection(dx, dy, source)
    local layout = self:_getOverlayLayout()
    local previous = self._overlaySelectedKey
    local rowIndex, colIndex = self:_findOverlayKeyPosition(self._overlaySelectedKey)
    local nextRow = math.max(1, math.min(#layout, rowIndex + dy))
    local nextCol = colIndex + dx
    local row = layout[nextRow]

    if nextCol < 1 then nextCol = 1 end
    if nextCol > #row then nextCol = #row end

    self._overlaySelectedKey = row[nextCol]
    if previous ~= self._overlaySelectedKey then
        self:_rumbleOverlayTap("nav", source)
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
        self:_moveOverlaySelection(0, -1, "joycon")
    end
    if triggered(B.BUTTON_DOWN) then
        self:_moveOverlaySelection(0, 1, "joycon")
    end
    if triggered(B.BUTTON_LEFT) then
        self:_moveOverlaySelection(-1, 0, "joycon")
    end
    if triggered(B.BUTTON_RIGHT) then
        self:_moveOverlaySelection(1, 0, "joycon")
    end

    local composingCn = self._overlayCn and (not self._overlayFn) and #self._overlayPinyin > 0

    if justPressed(B.BUTTON_A) then
        if composingCn then
            self:_commitOverlayIme(1, true)
        else
            self:_activateOverlayKey(self._overlaySelectedKey, "joycon")
        end
    end
    if justPressed(B.BUTTON_B, true) then
        if not self:_backspaceOverlayIme() then
            self:_backspaceOverlayBuffer()
        end
    end
    if justPressed(B.BUTTON_X) then
        self._overlayShift = not self._overlayShift
        self:_invalidate()
    end
    if justPressed(B.BUTTON_Y) then
        if composingCn then
            self:_commitOverlayIme(1, true)
        else
            self:_appendOverlayText(self:_applyOverlayModifiers(" "))
        end
    end
    if justPressed(B.BUTTON_LB) then
        if not (composingCn and self:_changeOverlayImePage(-1, "joycon")) then
            self:_sendInput(Platform.keyMap.TAB)
            self:_clearOverlayModifiers(false)
        end
    end
    if justPressed(B.BUTTON_RB) then
        if composingCn then
            self:_changeOverlayImePage(1, "joycon")
        end
    end
    if justPressed(B.BUTTON_START) then
        self:_openSystemIme()
    end
    if justPressed(B.BUTTON_RSB) then
        self:_toggleOverlayKeyboardVisible()
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

function TerminalView:_handleOverlayPointer(absX, absY, activate)
    if not self._overlayKeyboardVisible then
        return false
    end

    local target = self:_hitOverlayTarget(absX, absY)
    if not target then
        return self:_isPointInOverlay(absX, absY)
    end

    if target.type == "key" then
        local changed = self._overlaySelectedKey ~= target.key
        self._overlaySelectedKey = target.key
        if activate then
            self:_activateOverlayKey(target.key, "touch")
        elseif changed then
            self:_invalidate()
        end
        return true
    elseif target.type == "suggestion" then
        if activate then
            self:_applySuggestion(target.item, "touch")
        end
        return true
    end

    return self:_isPointInOverlay(absX, absY)
end

function TerminalView:_pollOverlayTouch()
    if not self._overlayKeyboardVisible then
        self._touchState.pressed = false
        self._overlayTouchRepeatKey = nil
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

    -- Handle repeat for backspace key (hold down to continuously delete)
    local nowMs = _nowMs()
    if self._overlayTouchRepeatKey and isPressed then
        local target = self:_hitOverlayTarget(touch.x, touch.y)
        if target and target.type == "key" then
            local targetKey = target.key
            local resolved = self:_resolveOverlayKey(targetKey)
            if resolved and resolved.action == "backspace" then
                local repeatState = self._overlayTouchRepeatState
                if repeatState and repeatState.nextAt > 0 and nowMs >= repeatState.nextAt then
                    repeatState.nextAt = nowMs + DPAD_REPEAT_INTERVAL_MS
                    self._overlayTouchRepeatState = repeatState
                    -- Trigger backspace again without activating (no rumble, no repeat setup)
                    self:_backspaceOverlayBuffer()
                end
            else
                -- Finger moved off backspace key or key changed
                self._overlayTouchRepeatKey = nil
                self._overlayTouchRepeatState = nil
            end
        else
            -- No target under finger
            self._overlayTouchRepeatKey = nil
            self._overlayTouchRepeatState = nil
        end
    end

    if isPressed then
        local target = self:_hitOverlayTarget(touch.x, touch.y)
        if target and target.type == "key" then
            self._overlaySelectedKey = target.key
            if not wasPressed or self._touchState.id ~= touch.id then
                self:_activateOverlayKey(target.key, "touch")
                -- Start repeat for backspace key
                local resolved = self:_resolveOverlayKey(target.key)
                if resolved and resolved.action == "backspace" then
                    self._overlayTouchRepeatKey = target.key
                    self._overlayTouchRepeatState = { nextAt = nowMs + DPAD_REPEAT_DELAY_MS }
                end
            end
        elseif target and target.type == "suggestion" then
            if not wasPressed or self._touchState.id ~= touch.id then
                self:_applySuggestion(target.item, "touch")
            end
        end
    else
        -- Release - stop repeat
        self._overlayTouchRepeatKey = nil
        self._overlayTouchRepeatState = nil
    end

    self._touchState = {
        pressed = isPressed,
        x = touch.x or 0,
        y = touch.y or 0,
        id = touch.id or -1,
    }
end

local function _pollPressed(button, controllerState)
    if controllerState and controllerState.isButtonPressed then
        local ok, pressed = pcall(function()
            return controllerState:isButtonPressed(button)
        end)

        if not ok then
            return false, tostring(pressed)
        end

        return pressed and true or false, nil
    end

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

    if not brls.Application.getControllerState and not brls.Application.isSwitchControllerButtonPressed and not brls.Application.isControllerButtonPressed then
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

    local controllerState = nil
    local current = {}
    local errors = {}
    local pollMode = "state"

    if brls.Application.getControllerState then
        local ok, state = pcall(function()
            return brls.Application.getControllerState()
        end)

        if ok and state and state.isButtonPressed then
            controllerState = state
        else
            pollMode = (Platform.isSwitch and brls.Application.isSwitchControllerButtonPressed) and "raw" or "brls"
        end
    else
        pollMode = (Platform.isSwitch and brls.Application.isSwitchControllerButtonPressed) and "raw" or "brls"
    end

    for _, button in ipairs(watched) do
        local pressed, err = _pollPressed(button, controllerState)
        current[button] = pressed
        if err then
            table.insert(errors, err)
        end
    end

    local rawButtons = controllerState and "snapshot" or (brls.Application.getSwitchButtonsDebug and brls.Application.getSwitchButtonsDebug() or "n/a")

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
        self:_toggleOverlayKeyboardVisible()
        self:_rumbleOverlayTap("nav", "joycon")
    end
    if justPressed(B.BUTTON_START) then
        _trace("[TerminalView] Polled + -> System IME")
        self:_openSystemIme()
    end
    if justPressed(B.BUTTON_BACK) then
        _trace("[TerminalView] Polled - -> Close")
        if self._overlayKeyboardVisible then
            self._overlayKeyboardVisible = false
            self:_invalidate()
        else
            if self._onCloseRequest then
                self._onCloseRequest()
            elseif self._ssh:isConnected() then
                self._ssh:disconnect()
            end
        end
    end

    self._lastPolledButtons = current
end

function TerminalView:_drawKeyboardOverlay(vg, x, y, w, h)
    local rawX, rawY, rawW, rawH = x, y, w, h
    x, y, w, h = _getOverlayLogicalRect(x, y, w, h)

    local compactLayout = self:_isCompactOverlayLayout()
    local panelInset = compactLayout and 0 or 12
    local contentInset = compactLayout and 4 or 12
    local modeLabel = compactLayout and "COMPACT" or "CLASSIC"
    local fnPageName = (self._overlayFn and OVERLAY_COMPACT_FN_PAGES[self._overlayFnPage or 1] and OVERLAY_COMPACT_FN_PAGES[self._overlayFnPage or 1].name) or "-"
    local panelX = x + panelInset
    local panelW = w - panelInset * 2
    local headerH = compactLayout and 20 or ((h < 560) and 26 or 30)
    local suggestions = self:_collectOverlaySuggestions()
    local chipsH = (#suggestions > 0) and 52 or 0
    local chipsGap = (#suggestions > 0) and 8 or 0
    local topInset = compactLayout and 0 or 8
    local bottomInset = compactLayout and 0 or 4
    local chipsReserve = chipsH + chipsGap
    local footerH = 0
    local rowGap = compactLayout and 1 or 2
    local keyGap = compactLayout and 2 or 4
    local rows = self:_getOverlayLayout()
    local contentW = panelW - contentInset * 2
    local keyH = 0
    local panelH = 0

    if compactLayout then
        local squareKeySize = nil
        for _, row in ipairs(rows) do
            local units = 0
            for _, key in ipairs(row) do
                units = units + (key.width or 1)
            end

            local keyUnitW = (contentW - keyGap * (#row - 1)) / units
            if not squareKeySize or keyUnitW < squareKeySize then
                squareKeySize = keyUnitW
            end
        end

        keyH = math.max(24, math.floor((squareKeySize or 0) * 0.75 + 0.5)) -- 键帽高度
        panelH = headerH + 6 + keyH * #rows + rowGap * (#rows - 1)
    else
        local maxPanelH = h - topInset - bottomInset - chipsReserve
        if maxPanelH < 180 then
            maxPanelH = h - bottomInset
        end

        local narrowestUnitW = nil
        for _, row in ipairs(rows) do
            local units = 0
            for _, key in ipairs(row) do
                units = units + (key.width or 1)
            end

            local keyUnitW = (contentW - keyGap * (#row - 1)) / units
            if not narrowestUnitW or keyUnitW < narrowestUnitW then
                narrowestUnitW = keyUnitW
            end
        end

        local keyHByWidth = math.floor((narrowestUnitW or 0) * 0.72 + 0.5)
        local rowAreaH = math.max(0, maxPanelH - headerH - footerH - 6)
        local keyHByHeight = math.floor((rowAreaH - rowGap * (#rows - 1)) / #rows)
        keyH = math.min(keyHByWidth, keyHByHeight)
        if keyH < 28 then keyH = 28 end

        panelH = headerH + 6 + keyH * #rows + rowGap * (#rows - 1)
        if panelH > maxPanelH then
            keyH = math.floor((maxPanelH - headerH - footerH - 6 - rowGap * (#rows - 1)) / #rows)
            if keyH < 24 then keyH = 24 end
            panelH = headerH + 6 + keyH * #rows + rowGap * (#rows - 1)
        end
    end

    local panelY = y + h - panelH - bottomInset

    self._overlayTouchTargets = {}
    self._overlayPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }

    local nowMs = math.floor((os.clock() or 0) * 1000)
    if (not self._overlayDrawLogAt) or (nowMs - self._overlayDrawLogAt >= 800) then
        self._overlayDrawLogAt = nowMs
        _debug(string.format(
            "[TerminalView] Overlay draw: raw=%dx%d logical=%dx%d panelX=%d panelY=%d panelW=%d panelH=%d mode=%s",
            math.floor(rawW or 0),
            math.floor(rawH or 0),
            math.floor(w or 0),
            math.floor(h or 0),
            math.floor(panelX or 0),
            math.floor(panelY or 0),
            math.floor(panelW or 0),
            math.floor(panelH or 0),
            compactLayout and "compact" or "classic"
        ))
    end

    nvgBeginPath(vg)
    nvgRect(vg, panelX + 1, panelY + 2, panelW, panelH)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.panel_shadow, 32))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRect(vg, panelX, panelY, panelW, panelH)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.panel_fill, 245))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRect(vg, panelX + 0.5, panelY + 0.5, panelW - 1, panelH - 1)
    nvgStrokeColor(vg, _withAlpha(OVERLAY_THEME.panel_border, 255))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    nvgFontFace(vg, "regular")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.title_text, 255))
    nvgText(vg, panelX + 10, panelY + headerH / 2, compactLayout and "Touch Keyboard Compact" or "Touch Keyboard")

    local overlayHintText = compactLayout and "Touch/A Type  B BS  X Shift  Y Space  Win+Fn Layout  ... More" or OVERLAY_HINT_TEXT
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.hint_text, 255))
    nvgText(vg, panelX + panelW / 2, panelY + headerH / 2, overlayHintText)

    local themeName = OVERLAY_THEME.name or "THEME"
    local imeMode = self._overlayCn and "\228\184\173" or "EN"
    local composeText = (#self._overlayPinyin > 0) and (" [" .. self._overlayPinyin .. "]") or ""
    local pageText = (#self._overlayImeCandidates > 0) and string.format(" %d/%d", self._overlayImePage or 1, self:_getOverlayImePageCount()) or ""
    local modeText = string.format("%s %s %s%s%s  Shift:%s Caps:%s Ctrl:%s Alt:%s Win:%s Fn:%s Pg:%s", themeName, modeLabel, imeMode, composeText, pageText, self._overlayShift and "1" or "0", self._overlayCaps and "1" or "0", self._overlayCtrl and "1" or "0", self._overlayAlt and "1" or "0", self._overlayMeta and "1" or "0", self._overlayFn and "1" or "0", fnPageName)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, _withAlpha(OVERLAY_THEME.mode_text, 255))
    nvgText(vg, panelX + panelW - 14, panelY + headerH / 2, modeText)

    local rowY = panelY + headerH + 4
    if chipsH > 0 then
        local chipBandY = panelY - chipsH - chipsGap
        local chipBandH = chipsH
        local chipInset = compactLayout and 4 or 10
        local chipX = panelX + chipInset
        local chipY = chipBandY + 4
        local chipH = chipBandH - 8

        nvgBeginPath(vg)
        nvgRect(vg, panelX + 1, chipBandY + 2, panelW, chipBandH)
        nvgFillColor(vg, _withAlpha(OVERLAY_THEME.panel_shadow, 26))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRect(vg, panelX, chipBandY, panelW, chipBandH)
        nvgFillColor(vg, _withAlpha(OVERLAY_THEME.panel_fill, 238))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRect(vg, panelX + 0.5, chipBandY + 0.5, panelW - 1, chipBandH - 1)
        nvgStrokeColor(vg, _withAlpha(OVERLAY_THEME.panel_border, 255))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        for index, item in ipairs(suggestions) do
            local chipLabel = item.display or item.text
            nvgFontSize(vg, 13)
            local chipW = math.max(82, math.min(196, 26 + #tostring(chipLabel) * 15))
            if chipX + chipW > panelX + panelW - chipInset then
                break
            end

            local chipPalette = _overlayChipPalette(index, item)
            nvgBeginPath(vg)
            nvgRect(vg, chipX, chipY, chipW, chipH)
            nvgFillColor(vg, chipPalette.fill)
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRect(vg, chipX + 0.5, chipY + 0.5, chipW - 1, chipH - 1)
            nvgStrokeColor(vg, chipPalette.border)
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)

            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, chipPalette.text)
            nvgText(vg, chipX + chipW / 2, chipY + chipH / 2, chipLabel)

            table.insert(self._overlayTouchTargets, {
                x = chipX,
                y = chipY,
                w = chipW,
                h = chipH,
                type = "suggestion",
                item = item,
            })

            chipX = chipX + chipW + 4
        end
    end
    for rowIndex, row in ipairs(rows) do
        local units = 0
        for _, key in ipairs(row) do
            units = units + (key.width or 1)
        end
        local keyUnitW = (contentW - keyGap * (#row - 1)) / units
        local keyX = panelX + contentInset

        for _, key in ipairs(row) do
            local keyW = keyUnitW * (key.width or 1)
            local selected = (self._overlaySelectedKey == key)
            local active = (key.action == "shift" and self._overlayShift)
                or (key.action == "caps" and self._overlayCaps)
                or (key.action == "ctrl" and self._overlayCtrl)
                or (key.action == "alt" and self._overlayAlt)
                or (key.action == "meta" and self._overlayMeta)
                or (key.action == "fn" and self._overlayFn)
                or (key.action == "fn_page" and self._overlayFn and (self._overlayFnPage or 1) > 1)
            local palette = _overlayKeyPalette(key, rowIndex, selected, active)

            nvgBeginPath(vg)
            nvgRect(vg, keyX, rowY, keyW, keyH)
            nvgFillColor(vg, palette.fill)
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRect(vg, keyX + 0.6, rowY + 0.6, keyW - 1.2, keyH - 1.2)
            nvgStrokeColor(vg, palette.border)
            nvgStrokeWidth(vg, (selected or active) and 2.0 or 1.2)
            nvgStroke(vg)

            nvgBeginPath(vg)
            nvgRect(vg, keyX + 2, rowY + 2, keyW - 4, math.max(6, keyH * 0.22))
            nvgFillColor(vg, palette.top)
            nvgFill(vg)

            local resolved = self:_resolveOverlayKey(key)
            local label = resolved.label
            if resolved.action == "char" then
                label = self:_resolveOverlayChar(resolved)
            end

            local labelSize = math.max(11, math.min(18, math.floor(keyH * 0.38 + 0.5)))
            if #tostring(label or "") >= 4 then
                labelSize = labelSize - 3
            elseif #tostring(label or "") >= 3 then
                labelSize = labelSize - 2
            end
            nvgFontSize(vg, labelSize)
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

    if w and h and w > 0 and h > 0 then
        if self._lastDrawWidth ~= w or self._lastDrawHeight ~= h then
            self._lastDrawWidth = w
            self._lastDrawHeight = h
            _debug(string.format("[TerminalView] Draw area changed: x=%d y=%d w=%d h=%d",
                math.floor(x or 0), math.floor(y or 0), math.floor(w or 0), math.floor(h or 0)))
            self:resize(w, h)
        end
    end

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
        _debug("[TerminalView] Sending input: '" .. data:gsub("\r", "\\r"):gsub("\n", "\\n") .. "' (" .. #data .. " bytes)")
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
        return self:_handleOverlayPointer(event.x, event.y, true)
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
        return self:_handleOverlayPointer(event.x, event.y, false)
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
        return self:_handleOverlayPointer(event.x, event.y, false)
    end

    if not self._selecting then return false end
    self._selecting = false
    
    if self._selection.startRow == self._selection.endRow and 
       math.abs(self._selection.startCol - self._selection.endCol) < 2 then
        self._selection = nil
    else
        local text = self:getSelectedText()
        if text and #text > 0 then
            local copied = false
            local platform = brls.Application.getPlatform()
            if platform and platform.pasteToClipboard then
                copied = pcall(function()
                    platform:pasteToClipboard(text)
                end)
            end
            self:setStatus(copied and "已复制到剪贴板" or "已选择文本", 100, 255, 100)
            brls.delay(1500, function()
                self:setStatus(self._ssh:isConnected() and "已连接" or "未连接")
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
