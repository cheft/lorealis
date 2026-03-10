-- =============================================================
-- platform.lua — 跨平台检测与输入适配层
-- 负责检测运行平台（Switch / Desktop），并统一输入事件接口
-- =============================================================

local Platform = {}

-- ── 平台检测 ─────────────────────────────────────────────────
-- brls.Application.getPlatform():getName() 在 Switch 上返回 "Switch"
local function _detectPlatform()
    local ok, platform = pcall(function()
        return brls.Application.getPlatform()
    end)
    if ok and platform then
        local name = platform:getName() or ""
        if name == "Switch" then
            return "switch"
        end
    end
    return "desktop"
end

Platform.name = _detectPlatform()       -- "switch" | "desktop"
Platform.isSwitch  = (Platform.name == "switch")
Platform.isDesktop = (Platform.name == "desktop")

-- ── 终端默认尺寸（字符列/行数）──────────────────────────────
-- Switch 1280×720 @ 字体12px ≈ 106×45，保守取 100×40
-- Desktop 按窗口实际尺寸动态计算
if Platform.isSwitch then
    Platform.defaultCols = 100
    Platform.defaultRows = 36
else
    Platform.defaultCols = 120
    Platform.defaultRows = 40
end

-- ── 输入键码映射（统一为 VT100/xterm 转义串）──────────────
-- 供 keyboard.lua 和终端视图调用
Platform.keyMap = {
    -- 方向键
    UP    = "\27[A",
    DOWN  = "\27[B",
    RIGHT = "\27[C",
    LEFT  = "\27[D",
    -- 功能键
    HOME  = "\27[H",
    END   = "\27[F",
    PGUP  = "\27[5~",
    PGDN  = "\27[6~",
    DEL   = "\27[3~",
    INS   = "\27[2~",
    F1    = "\27OP",
    F2    = "\27OQ",
    F3    = "\27OR",
    F4    = "\27OS",
    F5    = "\27[15~",
    F6    = "\27[17~",
    F7    = "\27[18~",
    F8    = "\27[19~",
    F9    = "\27[20~",
    F10   = "\27[21~",
    F11   = "\27[23~",
    F12   = "\27[24~",
    -- 控制键
    ENTER = "\r",
    TAB   = "\t",
    ESC   = "\27",
    BS    = "\8",    -- Backspace (^H)
    DEL_CHAR = "\127", -- Delete (^?)
    -- Ctrl 组合键 (^A … ^Z)
    CTRL_C = "\3",
    CTRL_D = "\4",
    CTRL_Z = "\26",
    CTRL_L = "\12",
    CTRL_A = "\1",
    CTRL_E = "\5",
    CTRL_U = "\21",
    CTRL_K = "\11",
    CTRL_W = "\23",
    CTRL_R = "\18",
}

-- ── Switch 手柄 → 终端操作映射说明 ───────────────────────────
--[[
  Switch 游戏手柄操作映射建议：
  ┌──────────────┬──────────────────────────────────────┐
  │ 按键          │ 终端操作                              │
  ├──────────────┼──────────────────────────────────────┤
  │ 左摇杆上下左右 │ 方向键 ↑↓←→                          │
  │ 右摇杆上下     │ 翻页 PgUp/PgDn（滚动缓冲区）           │
  │ A             │ 弹出虚拟键盘                           │
  │ B             │ Backspace                             │
  │ X             │ 发送 Ctrl+C                           │
  │ Y             │ 发送 Ctrl+D (EOF)                    │
  │ L             │ Tab 补全                              │
  │ R             │ Enter                                │
  │ ZL            │ 呼出命令快捷菜单                       │
  │ ZR            │ 断开/重连                             │
  │ +             │ 退出 SSH 返回连接列表                  │
  │ -             │ 切换全屏/窗口模式                      │
  └──────────────┴──────────────────────────────────────┘
--]]

-- ── 获取平台信息字符串（调试用）────────────────────────────
function Platform.info()
    return string.format(
        "Platform: %s | Cols: %d | Rows: %d",
        Platform.name, Platform.defaultCols, Platform.defaultRows
    )
end

return Platform
