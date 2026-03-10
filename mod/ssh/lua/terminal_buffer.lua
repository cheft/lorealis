-- =============================================================
-- terminal_buffer.lua — 终端屏幕缓冲区
-- 维护终端网格、滚动历史和 ANSI 操作应用
-- =============================================================




local TerminalBuffer = {}
TerminalBuffer.__index = TerminalBuffer

local function defaultAttr()
    return {
        fg        = {r=204, g=204, b=204, a=255},
        bg        = {r=  0, g=  0, b=  0, a=255},
        bold      = false,
        italic    = false,
        underline = false,
        reverse   = false,
    }
end

local function emptyCell(attr)
    return {ch=" ", attr=attr or defaultAttr()}
end

local function cloneAttr(attr)
    if not attr then
        return defaultAttr()
    end

    local cloned = {
        fg = attr.fg and { r = attr.fg.r, g = attr.fg.g, b = attr.fg.b, a = attr.fg.a } or { r = 204, g = 204, b = 204, a = 255 },
        bg = attr.bg and { r = attr.bg.r, g = attr.bg.g, b = attr.bg.b, a = attr.bg.a } or { r = 0, g = 0, b = 0, a = 255 },
        bold = attr.bold and true or false,
        italic = attr.italic and true or false,
        underline = attr.underline and true or false,
        reverse = attr.reverse and true or false,
    }

    return cloned
end

local function cloneCell(cell)
    if not cell then
        return emptyCell()
    end

    return {
        ch = cell.ch or " ",
        attr = cloneAttr(cell.attr),
        widePlaceholder = cell.widePlaceholder and true or false,
    }
end

local function cloneRow(row, cols)
    local copied = {}
    for c = 1, cols do
        copied[c] = cloneCell(row and row[c] or nil)
    end
    return copied
end

function TerminalBuffer.new(cols, rows, scrollback)
    local self = setmetatable({}, TerminalBuffer)
    self.cols       = cols or 80
    self.rows       = rows or 24
    self.scrollback = scrollback or 500

    self.screen  = {}
    for r = 1, self.rows do
        self.screen[r] = self:_newRow()
    end

    self.history = {}

    self.curRow  = 1
    self.curCol  = 1

    self.savedRow = 1
    self.savedCol = 1

    self.scrollTop    = 1
    self.scrollBottom = self.rows

    self.cursorVisible = true

    self.dirtyRows = {}
    self.allDirty  = true

    return self
end

function TerminalBuffer:resize(cols, rows)
    local oldCols = self.cols
    local oldRows = self.rows
    self.cols = cols
    self.rows = rows
    self.scrollBottom = rows

    for r = 1, #self.screen do
        local row = self.screen[r]
        for c = oldCols + 1, cols do
            row[c] = emptyCell()
        end
        for c = cols + 1, oldCols do
            row[c] = nil
        end
    end

    for r = oldRows + 1, rows do
        self.screen[r] = self:_newRow()
    end
    for r = rows + 1, oldRows do
        self.screen[r] = nil
    end

    self.curRow  = math.min(self.curRow, rows)
    self.curCol  = math.min(self.curCol, cols)
    self.allDirty = true
end

function TerminalBuffer:applyOps(ops)
    for _, op in ipairs(ops) do
        self:_applyOp(op)
    end
    print(string.format("[TerminalBuffer] After Ops: Cursor=(%d,%d)", self.curRow, self.curCol))
end

function TerminalBuffer:_applyOp(op)
    local t = op.type

    if t == "text" then
        self:_writeText(op.text, op.attr)

    elseif t == "lf" then
        self:_lineFeed()
    elseif t == "cr" then
        self.curCol = 1
    elseif t == "bs" then
        self.curCol = math.max(1, self.curCol - 1)
    elseif t == "tab" then
        local next = math.floor((self.curCol - 1) / 8) * 8 + 9
        self.curCol = math.min(next, self.cols)

    elseif t == "cursor_pos" then
        self.curRow = math.max(1, math.min(op.row, self.rows))
        self.curCol = math.max(1, math.min(op.col, self.cols))
    elseif t == "cursor_up" then
        self.curRow = math.max(self.scrollTop, self.curRow - op.n)
    elseif t == "cursor_down" then
        self.curRow = math.min(self.scrollBottom, self.curRow + op.n)
    elseif t == "cursor_left" then
        self.curCol = math.max(1, self.curCol - op.n)
    elseif t == "cursor_right" then
        self.curCol = math.min(self.cols, self.curCol + op.n)
    elseif t == "cursor_col" then
        self.curCol = math.max(1, math.min(op.col, self.cols))
    elseif t == "cursor_row" then
        self.curRow = math.max(1, math.min(op.row, self.rows))
    elseif t == "cursor_save" then
        self.savedRow = self.curRow
        self.savedCol = self.curCol
    elseif t == "cursor_restore" then
        self.curRow = self.savedRow
        self.curCol = self.savedCol
    elseif t == "cursor_show" then
        self.cursorVisible = true
    elseif t == "cursor_hide" then
        self.cursorVisible = false

    elseif t == "erase_screen" then
        for r = 1, self.rows do
            self.screen[r] = self:_newRow()
            self.dirtyRows[r] = true
        end
        self.curRow = 1; self.curCol = 1
    elseif t == "erase_below" then
        self:_fillCells(self.curRow, self.curCol, self.rows, self.cols, " ")
    elseif t == "erase_above" then
        self:_fillCells(1, 1, self.curRow, self.curCol, " ")
    elseif t == "erase_line" then
        self.screen[self.curRow] = self:_newRow()
        self.dirtyRows[self.curRow] = true
    elseif t == "erase_line_right" then
        local row = self.screen[self.curRow]
        for c = self.curCol, self.cols do row[c] = emptyCell() end
        self.dirtyRows[self.curRow] = true
    elseif t == "erase_line_left" then
        local row = self.screen[self.curRow]
        for c = 1, self.curCol do row[c] = emptyCell() end
        self.dirtyRows[self.curRow] = true

    elseif t == "scroll_up" then
        for _ = 1, op.n do self:_scrollUp() end
    elseif t == "scroll_down" then
        for _ = 1, op.n do self:_scrollDown() end

    elseif t == "insert_lines" then
        for _ = 1, op.n do self:_insertLineAt(self.curRow) end
    elseif t == "delete_lines" then
        for _ = 1, op.n do self:_deleteLineAt(self.curRow) end

    elseif t == "insert_chars" then
        local row = self.screen[self.curRow]
        for _ = 1, op.n do
            table.remove(row, self.cols)
            table.insert(row, self.curCol, emptyCell())
        end
        self.dirtyRows[self.curRow] = true
    elseif t == "delete_chars" then
        local row = self.screen[self.curRow]
        for _ = 1, op.n do
            table.remove(row, self.curCol)
            row[self.cols] = emptyCell()
        end
        self.dirtyRows[self.curRow] = true

    elseif t == "scroll_region" then
        self.scrollTop    = math.max(1, op.top)
        self.scrollBottom = op.bottom == 0 and self.rows or math.min(self.rows, op.bottom)

    elseif t == "reset_all" then
        self:_reset()
    end
end

function TerminalBuffer:_writeText(text, attr)
    local i = 1
    while i <= #text do
        local byte = text:byte(i)
        local cp, clen

        if byte < 0x80 then
            clen = 1
        elseif byte < 0xE0 then
            clen = 2
        elseif byte < 0xF0 then
            clen = 3
        else
            clen = 4
        end

        local ch = text:sub(i, i + clen - 1)
        i = i + clen

        local isWide = self:_isWideChar(byte, text:byte(i - clen + 1) or 0)

        if self.curCol > self.cols then
            self:_lineFeed()
            self.curCol = 1
        end

        local row = self.screen[self.curRow]
        if row then
            row[self.curCol] = {ch=ch, attr=attr or defaultAttr(), wide=isWide}
            self.dirtyRows[self.curRow] = true
            self.curCol = self.curCol + 1
            if isWide then
                if self.curCol <= self.cols then
                    row[self.curCol] = {ch="", attr=attr or defaultAttr(), widePlaceholder=true}
                end
                self.curCol = self.curCol + 1
            end
        end
    end
end

function TerminalBuffer:_lineFeed()
    if self.curRow == self.scrollBottom then
        self:_scrollUp()
    else
        self.curRow = math.min(self.rows, self.curRow + 1)
    end
end

function TerminalBuffer:_scrollUp()
    if self.scrollTop == 1 then
        self.history[#self.history + 1] = cloneRow(self.screen[self.scrollTop], self.cols)
        if #self.history > self.scrollback then
            table.remove(self.history, 1)
        end
    end
    for r = self.scrollTop, self.scrollBottom - 1 do
        self.screen[r] = self.screen[r + 1]
        self.dirtyRows[r] = true
    end
    self.screen[self.scrollBottom] = self:_newRow()
    self.dirtyRows[self.scrollBottom] = true
end

function TerminalBuffer:_scrollDown()
    for r = self.scrollBottom, self.scrollTop + 1, -1 do
        self.screen[r] = self.screen[r - 1]
        self.dirtyRows[r] = true
    end
    self.screen[self.scrollTop] = self:_newRow()
    self.dirtyRows[self.scrollTop] = true
end

function TerminalBuffer:_insertLineAt(row)
    table.remove(self.screen, self.scrollBottom)
    table.insert(self.screen, row, self:_newRow())
    self.allDirty = true
end

function TerminalBuffer:_deleteLineAt(row)
    table.remove(self.screen, row)
    table.insert(self.screen, self.scrollBottom, self:_newRow())
    self.allDirty = true
end

function TerminalBuffer:_reset()
    for r = 1, self.rows do
        self.screen[r] = self:_newRow()
    end
    self.curRow = 1; self.curCol = 1
    self.scrollTop = 1; self.scrollBottom = self.rows
    self.allDirty = true
end

function TerminalBuffer:_fillCells(r1, c1, r2, c2, ch)
    for r = r1, r2 do
        local row = self.screen[r]
        if row then
            local cs = (r == r1) and c1 or 1
            local ce = (r == r2) and c2 or self.cols
            for c = cs, ce do
                row[c] = emptyCell()
            end
            self.dirtyRows[r] = true
        end
    end
end

function TerminalBuffer:_newRow()
    local row = {}
    for c = 1, self.cols do
        row[c] = emptyCell()
    end
    return row
end

function TerminalBuffer:_isWideChar(firstByte, secondByte)
    if firstByte < 0xE0 then return false end
    if firstByte >= 0xE2 and firstByte <= 0xE9 then return true end
    if firstByte == 0xEF and secondByte >= 0xBC then return true end
    return false
end

function TerminalBuffer:consumeDirty()
    if self.allDirty then
        self.allDirty = false
        self.dirtyRows = {}
        local all = {}
        for r = 1, self.rows do all[#all+1] = r end
        return all
    end
    local rows = {}
    for r, _ in pairs(self.dirtyRows) do
        rows[#rows+1] = r
    end
    self.dirtyRows = {}
    return rows
end

function TerminalBuffer:getRowText(r)
    local row = self.screen[r]
    if not row then return "" end
    local s = {}
    for c = 1, self.cols do
        s[c] = (row[c] and row[c].ch) or " "
    end
    return table.concat(s)
end

return TerminalBuffer
