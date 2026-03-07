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

local TerminalView = {}
TerminalView.__index = TerminalView

-- ── 字体/渲染参数 ─────────────────────────────────────────────
local FONT_SIZE    = Platform.isSwitch and 13 or 14  -- px（等宽字体）
local LINE_HEIGHT  = FONT_SIZE + 3                   -- 行高
local CHAR_WIDTH   = FONT_SIZE * 0.6                 -- 粗略字符宽度（等宽）
local PADDING_X    = 6
local PADDING_Y    = 4
local CURSOR_BLINK_INTERVAL = 500  -- ms

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

    -- 日志（用于调试输出）
    self._log            = {}
    self._logEnabled     = false

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
        -- 注册控制器输入
        view:registerAction("虚拟键盘", brls.ControllerButton.BUTTON_A, function()
            self._keyboard:openSwkbd()
            return true
        end, false)
        view:registerAction("Ctrl+C", brls.ControllerButton.BUTTON_X, function()
            self:_sendInput("\3")
            return true
        end, false)
        view:registerAction("断开/重连", brls.ControllerButton.BUTTON_RB, function()
            if self._ssh:isConnected() then
                self._ssh:disconnect()
            else
                self._ssh:reconnect()
            end
            return true
        end, false)

        -- 注册帧更新（光标闪烁 + 轮询驱动）
        view:registerFrameCallback(function(dt)
            self:_onFrame(dt)
        end)
    end
end

-- ── 接收 SSH 数据并更新缓冲区 ────────────────────────────────
function TerminalView:feedData(data)
    if not data or #data == 0 then return end
    local ops = self._parser:feed(data)
    self._buf:applyOps(ops)
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
        print("[SSH Terminal] Resized to {}x{}", newCols, newRows)
    end
end

-- ── 帧更新（光标闪烁）────────────────────────────────────────
function TerminalView:_onFrame(dt)
    self._blinkTimer = self._blinkTimer + dt
    if self._blinkTimer >= CURSOR_BLINK_INTERVAL then
        self._blinkTimer = self._blinkTimer - CURSOR_BLINK_INTERVAL
        self._blinkOn = not self._blinkOn
        self:_invalidate()
    end
end

-- ── NanoVG 绘制主函数 ────────────────────────────────────────
function TerminalView:_draw(vg, x, y, w, h)
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

    -- 计算渲染起始行（考虑历史滚动偏移）
    local histLen = #self._buf.history
    local startHistRow = histLen - self._scrollOffset - visRows + 1
    local startScreenRow = 1
    if startHistRow < 1 then
        startScreenRow = 1 - startHistRow + 1
        startHistRow   = 1
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
            nvgRect(vg, cx, drawY, CHAR_WIDTH, LINE_HEIGHT)
            nvgFillColor(vg, nvgRGBA(220, 220, 220, 180))
            nvgFill(vg)
        end
        drawY = drawY + LINE_HEIGHT
    end

    -- 状态栏（底部）
    self:_drawStatusBar(vg, x, y + h - 20, w, 20)

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

            -- 背景色（非默认时才绘制）
            local bg = attr.bg
            if bg.r ~= BG_R or bg.g ~= BG_G or bg.b ~= BG_B then
                nvgBeginPath(vg)
                nvgRect(vg, cx, y, cell.wide and CHAR_WIDTH * 2 or CHAR_WIDTH, LINE_HEIGHT)
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
                    nvgText(vg, cx + 0.5, y, ch, nil)
                end
                nvgText(vg, cx, y, ch, nil)
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

            cx = cx + (cell.wide and CHAR_WIDTH * 2 or CHAR_WIDTH)
        end
    end
end

-- ── 绘制底部状态栏 ───────────────────────────────────────────
function TerminalView:_drawStatusBar(vg, x, y, w, h)
    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(30, 30, 30, 230))
    nvgFill(vg)

    -- 状态文字
    nvgFontSize(vg, 11)
    nvgFontFace(vg, "regular")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local c = self._statusColor
    nvgFillColor(vg, nvgRGBA(c.r, c.g, c.b, 255))
    nvgText(vg, x + 4, y + h / 2, self._statusText, nil)

    -- 右侧终端尺寸
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 100, 100, 255))
    nvgText(vg, x + w - 4, y + h / 2,
        string.format("%dx%d", self._cols, self._rows), nil)
end

-- ── 绘制滚动指示器 ───────────────────────────────────────────
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
    if self._ssh:isConnected() then
        self._ssh:send(data)
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

return TerminalView
