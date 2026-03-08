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
        
        -- 注册控制器输入
        view:registerAction("虚拟键盘", brls.ControllerButton.BUTTON_A, function()
            self._keyboard:openSwkbd()
            return true
        end, false)
        -- Switch: BUTTON_START 对应 + 键
        view:registerAction("弹出键盘", brls.ControllerButton.BUTTON_START, function()
            print("[TerminalView] START(+) button pressed - opening keyboard")
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
        -- Y 按钮：弹出系统键盘
        view:registerAction("弹出键盘", brls.ControllerButton.BUTTON_Y, function()
            print("[TerminalView] Y button pressed - opening keyboard")
            self._keyboard:openSwkbd()
            return true
        end, false)
        -- Switch: BUTTON_BACK 对应 - 键
        view:registerAction("返回", brls.ControllerButton.BUTTON_BACK, function()
            print("[TerminalView] BACK(-) button pressed - closing terminal")
            if self._ssh:isConnected() then
                self._ssh:disconnect()
            end
            return true
        end, false)
        -- B 按钮：返回并关闭终端
        view:registerAction("返回", brls.ControllerButton.BUTTON_B, function()
            print("[TerminalView] B button pressed - closing terminal")
            if self._ssh:isConnected() then
                self._ssh:disconnect()
            end
            return true
        end, false)

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

        -- -- 注册鼠标/触摸事件（滚动与选择）
        -- view:onPointerDown(function(event)
        --     return self:_onPointerDown(event)
        -- end)
        -- view:onPointerMove(function(event)
        --     return self:_onPointerMove(event)
        -- end)
        -- view:onPointerUp(function(event)
        --     return self:_onPointerUp(event)
        -- end)
        -- view:onScroll(function(event)
        --     if event.y ~= 0 then
        --         if event.y > 0 then self:scrollUp(3) else self:scrollDown(3) end
        --         return true
        --     end
        --     return false
        -- end)
    end
end

-- ── 全局物理键盘事件监听 (单例订阅，避免内存泄漏) ──────────────
local function initGlobalKeyboardListeners()
    local inputManager = brls.Application.getPlatform():getInputManager()
    if not inputManager or not inputManager.getCharInputEvent then return end
    
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
    nvgText(vg, x + 4, y + h / 2, self._statusText)

    -- 右侧终端尺寸
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 100, 100, 255))
    nvgText(vg, x + w - 4, y + h / 2,
        string.format("%dx%d", self._cols, self._rows))
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
        print("[TerminalView] Sending input: '" .. data:gsub("\r", "\\r"):gsub("\n", "\\n") .. "' (" .. #data .. " bytes)")
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

-- ── 鼠标/指针事件处理 ─────────────────────────────────────────
function TerminalView:_onPointerDown(event)
    -- 计算点击的行列
    local histLen = #self._buf.history
    local visRows = math.floor((self._view:getHeight() - PADDING_Y * 2 - 20) / LINE_HEIGHT)
    local totalRows = histLen + self._rows
    local startLine = totalRows - self._scrollOffset - visRows + 1
    if startLine < 1 then startLine = 1 end

    local localX = event.x - self._view:getX() - PADDING_X
    local localY = event.y - self._view:getY() - PADDING_Y
    
    local r = math.floor(localY / LINE_HEIGHT) + startLine
    local c = math.floor(localX / CHAR_WIDTH) + 1
    
    self._selection = { startRow = r, startCol = c, endRow = r, endCol = c }
    self._selecting = true
    self:_invalidate()
    return true
end

function TerminalView:_onPointerMove(event)
    if not self._selecting then return false end
    
    local histLen = #self._buf.history
    local visRows = math.floor((self._view:getHeight() - PADDING_Y * 2 - 20) / LINE_HEIGHT)
    local totalRows = histLen + self._rows
    local startLine = totalRows - self._scrollOffset - visRows + 1
    if startLine < 1 then startLine = 1 end

    local localX = event.x - self._view:getX() - PADDING_X
    local localY = event.y - self._view:getY() - PADDING_Y
    
    local r = math.floor(localY / LINE_HEIGHT) + startLine
    local c = math.floor(localX / CHAR_WIDTH) + 1
    
    self._selection.endRow = r
    self._selection.endCol = c
    self:_invalidate()
    return true
end

function TerminalView:_onPointerUp(event)
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
