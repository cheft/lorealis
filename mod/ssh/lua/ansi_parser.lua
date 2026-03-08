-- =============================================================
-- ansi_parser.lua — ANSI/VT100 转义序列解析器
-- 将终端输出流解析为结构化的操作序列，供 terminal_buffer.lua 消费
-- 支持：SGR颜色、光标移动、清屏、删除行、256色/真彩色
-- =============================================================

local AnsiParser = {}
AnsiParser.__index = AnsiParser

-- ── SGR 颜色表（基本16色，映射到 NVG RGBA）──────────────────
-- 格式：{r, g, b}  (0-255)
local SGR_COLORS_DARK = {
    [0]  = {  0,   0,   0},  -- Black
    [1]  = {170,   0,   0},  -- Red
    [2]  = {  0, 170,   0},  -- Green
    [3]  = {170, 170,   0},  -- Yellow
    [4]  = {  0,   0, 170},  -- Blue
    [5]  = {170,   0, 170},  -- Magenta
    [6]  = {  0, 170, 170},  -- Cyan
    [7]  = {170, 170, 170},  -- White
    -- 高亮版本 (bright)
    [8]  = { 85,  85,  85},  -- Bright Black (gray)
    [9]  = {255,  85,  85},  -- Bright Red
    [10] = { 85, 255,  85},  -- Bright Green
    [11] = {255, 255,  85},  -- Bright Yellow
    [12] = { 85,  85, 255},  -- Bright Blue
    [13] = {255,  85, 255},  -- Bright Magenta
    [14] = { 85, 255, 255},  -- Bright Cyan
    [15] = {255, 255, 255},  -- Bright White
}

-- xterm 256 色立方（6×6×6 + 24 灰度）
local function xterm256ToRGB(idx)
    if idx < 16 then
        local c = SGR_COLORS_DARK[idx]
        return c and {c[1], c[2], c[3]} or {0, 0, 0}
    elseif idx < 232 then
        -- 6×6×6 color cube
        local i = idx - 16
        local b = i % 6;   i = math.floor(i / 6)
        local g = i % 6;   i = math.floor(i / 6)
        local r = i % 6
        local function v(x) return x == 0 and 0 or (55 + x * 40) end
        return {v(r), v(g), v(b)}
    else
        -- 24-step grayscale
        local gray = 8 + (idx - 232) * 10
        return {gray, gray, gray}
    end
end

-- ── 默认前景/背景色 ──────────────────────────────────────────
local DEFAULT_FG = {r=204, g=204, b=204, a=255}
local DEFAULT_BG = {r=  0, g=  0, b=  0, a=255}

-- ── 构造函数 ─────────────────────────────────────────────────
function AnsiParser.new()
    local self = setmetatable({}, AnsiParser)
    self:_reset()
    return self
end

function AnsiParser:_reset()
    self._buf      = ""   -- 未解析的原始字节缓冲
    self._ops      = {}   -- 输出：解析后的操作列表
    -- 当前 SGR 属性状态
    self._attr = {
        fg     = {r=DEFAULT_FG.r, g=DEFAULT_FG.g, b=DEFAULT_FG.b, a=255},
        bg     = {r=DEFAULT_BG.r, g=DEFAULT_BG.g, b=DEFAULT_BG.b, a=255},
        bold   = false,
        italic = false,
        underline = false,
        blink     = false,
        reverse   = false,
        invisible = false,
    }
end

-- ── 将原始数据推入解析器 ─────────────────────────────────────
-- 返回操作列表（table of op），消费后清空内部 ops
---@param data string  原始终端输出（可包含部分转义序列）
---@return table  操作列表
function AnsiParser:feed(data)
    local hex = {}
    for i=1,#data do hex[#hex+1] = string.format("%02X", data:byte(i)) end
    print("[AnsiParser] hex: " .. table.concat(hex, " "))
    
    local oldLen = #self._buf
    self._buf = self._buf .. data
    self._ops = {}
    self:_parse()
    print(string.format("[AnsiParser] feed: %d bytes -> %d ops (buf remained: %d)", #data, #self._ops, #self._buf))
    return self._ops
end

-- ── 内部解析主循环 ────────────────────────────────────────────
function AnsiParser:_parse()
    local buf = self._buf
    local i   = 1
    local len = #buf

    while i <= len do
        local byte = buf:byte(i)

        -- ── ESC 序列入口 ────────────────────────────────────
        if byte == 0x1B then  -- ESC
            -- 需要至少 2 字节才能判断序列类型
            if i + 1 > len then
                break  -- 等待更多数据
            end
            local next = buf:byte(i + 1)

            -- CSI: ESC [ …
            if next == 0x5B then  -- '['
                local seq_start = i + 2
                -- 查找终止符 (0x40-0x7E)
                local j = seq_start
                while j <= len and (buf:byte(j) < 0x40 or buf:byte(j) > 0x7E) do
                    j = j + 1
                end
                if j > len then break end  -- 序列不完整，等待

                local params_str = buf:sub(seq_start, j - 1)
                local final_char = buf:sub(j, j)
                self:_handleCSI(params_str, final_char)
                i = j + 1

            -- OSC: ESC ] … ST (ESC\) or BEL
            elseif next == 0x5D then  -- ']'
                -- 查找终止 ST=ESC\ 或 BEL=\7
                local j = i + 2
                while j <= len do
                    local c = buf:byte(j)
                    if c == 0x07 then  -- BEL
                        i = j + 1
                        break
                    elseif c == 0x1B and j + 1 <= len and buf:byte(j + 1) == 0x5C then
                        i = j + 2
                        break
                    end
                    j = j + 1
                end
                if j > len then break end  -- 不完整

            -- ESC c = 全部重置
            elseif next == 0x63 then
                self:_emit({type="reset_all"})
                i = i + 2

            -- 其他双字节 ESC 序列直接跳过
            else
                i = i + 2
            end

        -- ── 控制字符 ────────────────────────────────────────
        elseif byte == 0x0A then  -- LF (换行)
            self:_emit({type="lf"})
            i = i + 1
        elseif byte == 0x0D then  -- CR
            self:_emit({type="cr"})
            i = i + 1
        elseif byte == 0x08 then  -- BS
            self:_emit({type="bs"})
            i = i + 1
        elseif byte == 0x09 then  -- HT (Tab)
            self:_emit({type="tab"})
            i = i + 1
        elseif byte == 0x07 then  -- BEL（忽略）
            i = i + 1

        -- ── 普通可打印字符（UTF-8 安全）────────────────────
        else
            -- 收集连续的非转义字节（批量写入，性能优化）
            local start = i
            while i <= len do
                local b = buf:byte(i)
                if b == 0x1B or b == 0x0A or b == 0x0D or b == 0x08 or b == 0x09 or b == 0x07 then
                    break
                end
                i = i + 1
            end
            local text = buf:sub(start, i - 1)
            if #text > 0 then
                self:_emit({
                    type = "text",
                    text = text,
                    attr = self:_cloneAttr(),
                })
            end
        end
    end

    -- 保存未解析部分
    self._buf = buf:sub(i)
end

-- ── CSI 序列处理 ─────────────────────────────────────────────
function AnsiParser:_handleCSI(params, final)
    -- 解析参数（以 ';' 分隔的数字列表）
    local nums = {}
    for s in (params .. ";"):gmatch("([^;]*);") do
        nums[#nums + 1] = tonumber(s) or 0
    end
    if #nums == 0 then nums = {0} end

    -- CUP: 光标位置 ESC[row;colH  /  ESC[row;colf
    if final == "H" or final == "f" then
        self:_emit({type="cursor_pos", row=math.max(1,nums[1] or 1), col=math.max(1,nums[2] or 1)})

    -- CUU/CUD/CUF/CUB: 光标移动
    elseif final == "A" then self:_emit({type="cursor_up",    n=math.max(1,nums[1])})
    elseif final == "B" then self:_emit({type="cursor_down",  n=math.max(1,nums[1])})
    elseif final == "C" then self:_emit({type="cursor_right", n=math.max(1,nums[1])})
    elseif final == "D" then self:_emit({type="cursor_left",  n=math.max(1,nums[1])})

    -- 光标绝对行/列
    elseif final == "G" then self:_emit({type="cursor_col",   col=math.max(1,nums[1])})
    elseif final == "d" then self:_emit({type="cursor_row",   row=math.max(1,nums[1])})

    -- 保存/恢复光标
    elseif final == "s" then self:_emit({type="cursor_save"})
    elseif final == "u" then self:_emit({type="cursor_restore"})

    -- ED: 清屏  ESC[0J/1J/2J/3J
    elseif final == "J" then
        local n = nums[1]
        if     n == 0 then self:_emit({type="erase_below"})
        elseif n == 1 then self:_emit({type="erase_above"})
        elseif n == 2 or n == 3 then self:_emit({type="erase_screen"})
        end

    -- EL: 清行  ESC[0K/1K/2K
    elseif final == "K" then
        local n = nums[1]
        if     n == 0 then self:_emit({type="erase_line_right"})
        elseif n == 1 then self:_emit({type="erase_line_left"})
        elseif n == 2 then self:_emit({type="erase_line"})
        end

    -- IL/DL: 插入/删除行
    elseif final == "L" then self:_emit({type="insert_lines", n=math.max(1,nums[1])})
    elseif final == "M" then self:_emit({type="delete_lines", n=math.max(1,nums[1])})

    -- DCH/ICH: 删除/插入字符
    elseif final == "P" then self:_emit({type="delete_chars", n=math.max(1,nums[1])})
    elseif final == "@" then self:_emit({type="insert_chars", n=math.max(1,nums[1])})

    -- DECSTBM: 设置滚动区域
    elseif final == "r" then
        self:_emit({type="scroll_region", top=nums[1] or 1, bottom=nums[2] or 0})

    -- SD/SU: 滚动
    elseif final == "S" then self:_emit({type="scroll_up",   n=math.max(1,nums[1])})
    elseif final == "T" then self:_emit({type="scroll_down", n=math.max(1,nums[1])})

    -- SGR: 选择图形格式（颜色/加粗等）
    elseif final == "m" then
        self:_handleSGR(nums)

    -- SM/RM: 私有模式设置/复位（光标显示等）
    elseif final == "h" then
        if params == "?25" then self:_emit({type="cursor_show"}) end
    elseif final == "l" then
        if params == "?25" then self:_emit({type="cursor_hide"}) end

    -- DSR: Device Status Report
    elseif final == "n" then
        if nums[1] == 6 then
            self:_emit({type="dsr_report"})
        end

    -- DA: Device Attributes（终端能力查询，忽略）
    -- 其他未识别序列：直接忽略
    else
        -- print("[AnsiParser] Unknown CSI: ESC[" .. params .. final)
    end
end

-- ── SGR (Select Graphic Rendition) 处理 ─────────────────────
function AnsiParser:_handleSGR(nums)
    local i = 1
    while i <= #nums do
        local n = nums[i]

        if n == 0 then
            -- 全部重置
            self._attr.fg        = {r=DEFAULT_FG.r, g=DEFAULT_FG.g, b=DEFAULT_FG.b, a=255}
            self._attr.bg        = {r=DEFAULT_BG.r, g=DEFAULT_BG.g, b=DEFAULT_BG.b, a=255}
            self._attr.bold      = false
            self._attr.italic    = false
            self._attr.underline = false
            self._attr.blink     = false
            self._attr.reverse   = false
            self._attr.invisible = false

        elseif n == 1 then self._attr.bold      = true
        elseif n == 3 then self._attr.italic    = true
        elseif n == 4 then self._attr.underline = true
        elseif n == 5 or n == 6 then self._attr.blink  = true
        elseif n == 7 then self._attr.reverse   = true
        elseif n == 8 then self._attr.invisible = true
        elseif n == 22 then self._attr.bold      = false
        elseif n == 23 then self._attr.italic    = false
        elseif n == 24 then self._attr.underline = false
        elseif n == 25 then self._attr.blink     = false
        elseif n == 27 then self._attr.reverse   = false
        elseif n == 28 then self._attr.invisible = false

        -- 标准前景色 30-37, 90-97
        elseif n >= 30 and n <= 37 then
            local c = SGR_COLORS_DARK[n - 30]
            self._attr.fg = {r=c[1], g=c[2], b=c[3], a=255}
        elseif n == 39 then
            self._attr.fg = {r=DEFAULT_FG.r, g=DEFAULT_FG.g, b=DEFAULT_FG.b, a=255}
        elseif n >= 90 and n <= 97 then
            local c = SGR_COLORS_DARK[n - 90 + 8]
            self._attr.fg = {r=c[1], g=c[2], b=c[3], a=255}

        -- 标准背景色 40-47, 100-107
        elseif n >= 40 and n <= 47 then
            local c = SGR_COLORS_DARK[n - 40]
            self._attr.bg = {r=c[1], g=c[2], b=c[3], a=255}
        elseif n == 49 then
            self._attr.bg = {r=DEFAULT_BG.r, g=DEFAULT_BG.g, b=DEFAULT_BG.b, a=255}
        elseif n >= 100 and n <= 107 then
            local c = SGR_COLORS_DARK[n - 100 + 8]
            self._attr.bg = {r=c[1], g=c[2], b=c[3], a=255}

        -- 256色/真彩色前景: 38;5;n  或  38;2;r;g;b
        elseif n == 38 then
            if nums[i+1] == 5 and nums[i+2] then
                local c = xterm256ToRGB(nums[i+2])
                self._attr.fg = {r=c[1], g=c[2], b=c[3], a=255}
                i = i + 2
            elseif nums[i+1] == 2 and nums[i+4] then
                self._attr.fg = {r=nums[i+2], g=nums[i+3], b=nums[i+4], a=255}
                i = i + 4
            end

        -- 256色/真彩色背景: 48;5;n  或  48;2;r;g;b
        elseif n == 48 then
            if nums[i+1] == 5 and nums[i+2] then
                local c = xterm256ToRGB(nums[i+2])
                self._attr.bg = {r=c[1], g=c[2], b=c[3], a=255}
                i = i + 2
            elseif nums[i+1] == 2 and nums[i+4] then
                self._attr.bg = {r=nums[i+2], g=nums[i+3], b=nums[i+4], a=255}
                i = i + 4
            end
        end

        i = i + 1
    end
end

-- ── 辅助：发射一个操作 ───────────────────────────────────────
function AnsiParser:_emit(op)
    self._ops[#self._ops + 1] = op
    if op.type == "text" then
        print("[AnsiParser] Emit text: '" .. op.text:gsub("\r", "\\r"):gsub("\n", "\\n") .. "'")
    end
end

-- ── 辅助：深拷贝当前属性（避免引用共享）────────────────────
function AnsiParser:_cloneAttr()
    local a = self._attr
    return {
        fg        = {r=a.fg.r, g=a.fg.g, b=a.fg.b, a=a.fg.a},
        bg        = {r=a.bg.r, g=a.bg.g, b=a.bg.b, a=a.bg.a},
        bold      = a.bold,
        italic    = a.italic,
        underline = a.underline,
        blink     = a.blink,
        reverse   = a.reverse,
        invisible = a.invisible,
    }
end

return AnsiParser
