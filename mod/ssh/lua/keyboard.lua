-- =============================================================
-- keyboard.lua — Switch 虚拟键盘 & 通用输入处理
-- Switch: 弹出系统软键盘（brls.Application.getSwkbd）
--         + 手柄按键映射到终端转义序列
-- Desktop: 捕获物理键盘输入
-- =============================================================

local Platform = require("platform")
local _dbgOk, DebugLog = pcall(require, "debug_log")
if not _dbgOk then DebugLog = nil end

local Keyboard = {}
Keyboard.__index = Keyboard

local function _trace(msg)
    print(msg)
    if DebugLog and DebugLog.append then
        pcall(function()
            DebugLog.append(msg)
        end)
    end
end

-- ── 构造函数 ─────────────────────────────────────────────────
---@param onInput function(data:string)  接收输入数据的回调
function Keyboard.new(onInput)
    local self = setmetatable({}, Keyboard)
    self._onInput    = onInput   -- 输入回调
    self._inputBuf   = ""        -- 输入缓冲（多字符组合键）
    self._swkbdOpen  = false     -- Switch 软键盘是否打开
    return self
end

-- ── 触发输入回调 ─────────────────────────────────────────────
function Keyboard:_emit(data)
    if self._onInput and data and #data > 0 then
        self._onInput(data)
    end
end

-- ============================================================
-- Switch 手柄按键处理
-- 由 TerminalView 在 handleController 中调用
-- ============================================================
---@param button integer  brls.ControllerButton 枚举值
---@return boolean  是否已消费此事件
function Keyboard:handleButton(button)
    local B = brls.ControllerButton
    local K = Platform.keyMap

    -- 方向键 → 光标移动
    if button == B.BUTTON_UP    then self:_emit(K.UP);    return true
    elseif button == B.BUTTON_DOWN  then self:_emit(K.DOWN);  return true
    elseif button == B.BUTTON_LEFT  then self:_emit(K.LEFT);  return true
    elseif button == B.BUTTON_RIGHT then self:_emit(K.RIGHT); return true

    -- A → 打开虚拟键盘
    elseif button == B.BUTTON_A then
        self:openSwkbd()
        return true

    -- B → Backspace
    elseif button == B.BUTTON_B then
        self:_emit(K.BS); return true

    -- X → Ctrl+C
    elseif button == B.BUTTON_X then
        self:_emit(K.CTRL_C); return true

    -- Y → Ctrl+D (EOF / logout)
    elseif button == B.BUTTON_Y then
        self:_emit(K.CTRL_D); return true

    -- L → Tab 补全
    elseif button == B.BUTTON_LB then
        self:_emit(K.TAB); return true

    -- R → Enter
    elseif button == B.BUTTON_RB then
        self:_emit(K.ENTER); return true

    -- LT → Page Up（回滚缓冲区，不发送到 SSH）
    -- RT → Page Down
    -- 这两个事件由 TerminalView 自行处理，这里不消费

    -- ZL → 显示快捷命令菜单（由调用方处理）
    -- ZR → 断开/重连（由调用方处理）
    end

    return false
end

-- ── 处理左摇杆（用于光标/滚动）────────────────────────────
-- dx/dy 为摇杆偏移量（-1.0 ~ 1.0）
-- 仅在摇杆超过阈值时发送
function Keyboard:handleStick(dx, dy)
    local THRESHOLD = 0.3
    if math.abs(dy) > THRESHOLD then
        if dy < -THRESHOLD then
            self:_emit(Platform.keyMap.UP)
        elseif dy > THRESHOLD then
            self:_emit(Platform.keyMap.DOWN)
        end
    end
    if math.abs(dx) > THRESHOLD then
        if dx < -THRESHOLD then
            self:_emit(Platform.keyMap.LEFT)
        elseif dx > THRESHOLD then
            self:_emit(Platform.keyMap.RIGHT)
        end
    end
end

-- ============================================================
-- Switch 系统软键盘
-- ============================================================
function Keyboard:openSwkbd(opts)
    _trace("[SSH Keyboard] openSwkbd called; isSwitch=" .. tostring(Platform.isSwitch) .. ", swkbdOpen=" .. tostring(self._swkbdOpen))
    if not Platform.isSwitch then
        -- Desktop 弹出一个简单的输入框作为降级方案
        self:_openFallbackInput(opts)
        return
    end
    if self._swkbdOpen then return end

    opts = opts or {}
    self._swkbdOpen = true

    -- 尝试使用 InputCell.openKeyboard 作为更可靠的弹键盘方案
    local ok, inputCell = pcall(function()
        return brls.InputCell.new()
    end)

    if ok and inputCell then
        -- 创建一个隐藏的 InputCell 并调用其 openKeyboard 方法
        -- 这是目前已知的、可以稳定在 Switch NRO 下弹出系统键盘的方式
        local title = opts.header or "SSH 输入"
        local hint = opts.guide or "输入命令"

        inputCell:init(title, "", function(text)
            -- 用户确认输入后回调
            self._swkbdOpen = false
            if text and #text > 0 then
                self:_emit(text .. "\r")
            end
        end, hint, opts.maxLen or 256)

        -- 调用 InputCell 内部的 openKeyboard 方法
        -- 这会使用 brls::Application::getImeManager()->openForText
        -- 比 brls.Application.openSwkbd 更可靠
        local ok2, imeOpenedOrErr = pcall(function()
            return inputCell:openKeyboard(opts.maxLen or 256)
        end)

        if (not ok2) or imeOpenedOrErr == false then
            self._swkbdOpen = false
            _trace("[SSH Keyboard] InputCell.openKeyboard failed: " .. tostring(imeOpenedOrErr))
            self:_openFallbackInput(opts)
        else
            _trace("[SSH Keyboard] InputCell.openKeyboard accepted by IME")
        end
        return
    end

    -- 降级：尝试旧的 brls.Application.openSwkbd
    local config = {
        type         = opts.type or "normal",
        headerText   = opts.header   or "输入命令",
        subText      = opts.sub      or "",
        guideText    = opts.guide    or "按 + 确认，按 - 取消",
        initialText  = opts.initial  or "",
        maxLength    = opts.maxLen   or 256,
        cancelable   = true,
    }

    local ok3, err3 = pcall(function()
        brls.Application.openSwkbd(config, function(confirmed, inputText)
            self._swkbdOpen = false
            if confirmed and inputText and #inputText > 0 then
                self:_emit(inputText .. "\r")
            end
        end)
    end)

    if not ok3 then
        self._swkbdOpen = false
        _trace("[SSH Keyboard] openSwkbd failed: " .. tostring(err3))
        self:_openFallbackInput(opts)
    end
end

-- ── 降级输入框（Desktop 或软键盘不可用时）──────────────────
function Keyboard:_openFallbackInput(opts)
    opts = opts or {}
    -- 使用 brls.Dialog + InputCell
    local dialog = brls.Dialog.new(opts.header or "SSH 输入")
    -- TODO: 根据实际 Borealis Lua API 调整
    -- 这里示意弹出一个可编辑输入对话框
    dialog:addButton("发送", function()
        local text = dialog:getInputText()
        if text and #text > 0 then
            self:_emit(text .. "\r")
        end
    end)
    dialog:addButton("取消", function() end)
    dialog:open()
end

-- ============================================================
-- Desktop 键盘原始输入（通过 brls key event）
-- 由 TerminalView 注册回调后调用
-- ============================================================
---@param keyCode integer  brls key code
---@param mods integer     修饰键位掩码（Shift/Ctrl/Alt）
---@return boolean  是否已消费
function Keyboard:handleKey(keyCode, mods)
    -- 修饰键掩码常量（GLFW/SDL 兼容）
    local MOD_CTRL  = 0x02
    local MOD_SHIFT = 0x01
    local MOD_ALT   = 0x04

    -- Lua 5.1 不支持 &，用取模判断位是否设置
    local ctrl  = (mods % 4) >= 2   -- 检查 MOD_CTRL (0x02) 位
    local shift = (mods % 2) >= 1   -- 检查 MOD_SHIFT (0x01) 位

    -- 方向键
    local ARROW_UP=265; local ARROW_DOWN=264; local ARROW_LEFT=263; local ARROW_RIGHT=262
    if keyCode == ARROW_UP    then self:_emit(Platform.keyMap.UP);    return true end
    if keyCode == ARROW_DOWN  then self:_emit(Platform.keyMap.DOWN);  return true end
    if keyCode == ARROW_LEFT  then self:_emit(Platform.keyMap.LEFT);  return true end
    if keyCode == ARROW_RIGHT then self:_emit(Platform.keyMap.RIGHT); return true end

    -- 功能键
    local KEY_HOME=268; local KEY_END=269; local KEY_PGUP=266; local KEY_PGDN=267
    local KEY_DEL=261;  local KEY_INS=260
    if keyCode == KEY_HOME  then self:_emit(Platform.keyMap.HOME);  return true end
    if keyCode == KEY_END   then self:_emit(Platform.keyMap.END);   return true end
    if keyCode == KEY_PGUP  then self:_emit(Platform.keyMap.PGUP);  return true end
    if keyCode == KEY_PGDN  then self:_emit(Platform.keyMap.PGDN);  return true end
    if keyCode == KEY_DEL   then self:_emit(Platform.keyMap.DEL);   return true end

    -- Enter / Tab / Esc / Backspace
    if keyCode == 257 then self:_emit("\r");                    return true end  -- Enter
    if keyCode == 258 then self:_emit(Platform.keyMap.TAB);    return true end  -- Tab
    if keyCode == 256 then self:_emit(Platform.keyMap.ESC);    return true end  -- Escape
    if keyCode == 259 then self:_emit(Platform.keyMap.DEL_CHAR); return true end  -- Backspace

    -- Ctrl+字母 → 控制字符
    if ctrl and keyCode >= 65 and keyCode <= 90 then
        -- Ctrl+A=1, Ctrl+B=2, ... Ctrl+Z=26
        local cc = string.char(keyCode - 64)
        self:_emit(cc)
        return true
    end

    -- 字母数字退避处理 (如果 CharInputEvent 没响应)
    if not ctrl then
        -- 字母 A-Z (65-90)
        if keyCode >= 65 and keyCode <= 90 then
            local char = string.char(keyCode + (shift and 0 or 32))
            self:_emit(char)
            return true
        end
        -- 数字 0-9 (48-57) 和常用符号
        local numShift = { [48]=")", [49]="!", [50]="@", [51]="#", [52]="$", [53]="%", [54]="^", [55]="&", [56]="*", [57]="(" }
        if keyCode >= 48 and keyCode <= 57 then
            local char = shift and numShift[keyCode] or string.char(keyCode)
            self:_emit(char)
            return true
        end
        -- 其他常用 ASCII 符号
        local symMap = {
            [32] = {" ", " "},   -- Space
            [39] = {"'", "\""},  -- ' "
            [44] = {",", "<"},   -- , <
            [45] = {"-", "_"},   -- - _
            [46] = {".", ">"},   -- . >
            [47] = {"/", "?"},   -- / ?
            [59] = {";", ":"},   -- ; :
            [61] = {"=", "+"},   -- = +
            [91] = {"[", "{"},   -- [ {
            [92] = {"\\", "|"},  -- \ |
            [93] = {"]", "}"},   -- ] }
            [96] = {"`", "~"},   -- ` ~
        }
        local sym = symMap[keyCode]
        if sym then
            self:_emit(shift and sym[2] or sym[1])
            return true
        end
    end

    -- 默认未处理
    return false
end

-- ── 处理字符输入（Unicode codepoint）────────────────────────
---@param codepoint integer  Unicode 码点
function Keyboard:handleChar(codepoint)
    -- 将 codepoint 编码为 UTF-8
    local ch
    if codepoint < 0x80 then
        ch = string.char(codepoint)
    elseif codepoint < 0x800 then
        ch = string.char(
            0xC0 + math.floor(codepoint / 64),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint < 0x10000 then
        ch = string.char(
            0xE0 + math.floor(codepoint / 4096),
            0x80 + (math.floor(codepoint / 64) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    else
        ch = string.char(
            0xF0 + math.floor(codepoint / 262144),
            0x80 + (math.floor(codepoint / 4096) % 0x40),
            0x80 + (math.floor(codepoint / 64)  % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end
    self:_emit(ch)
end

return Keyboard
