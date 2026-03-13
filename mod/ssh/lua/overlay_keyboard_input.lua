local TerminalView = require("terminal_view")

local OverlayKeyboardInput = {}

local function createInputTransport()
    return {
        send = function(_, _data)
            return true
        end,
        resize = function(_, _cols, _rows)
        end,
        isConnected = function()
            return false
        end,
        disconnect = function()
        end,
    }
end

local function createCanvas()
    local canvas = brls.LuaImage.new()
    if canvas.setWidth then
        canvas:setWidth(brls.Application.windowWidth())
    end
    if canvas.setHeight then
        canvas:setHeight(brls.Application.windowHeight())
    end
    if canvas.setGrow then
        canvas:setGrow(1.0)
    end
    canvas:setFocusable(true)
    return canvas
end

function OverlayKeyboardInput.open(opts)
    opts = opts or {}

    local closed = false
    local submitted = false
    local transport = createInputTransport()
    local terminal = TerminalView.new(transport, {
        keyboardOnly = true,
        statusText = opts.statusText or "终端虚拟键盘输入",
        onOverlaySubmit = function(text)
            if closed then
                return
            end

            submitted = true
            closed = true
            if opts.onSubmit then
                pcall(opts.onSubmit, text or "")
            end
            pcall(function()
                brls.Application.popActivity()
            end)
        end,
    })

    local canvas = createCanvas()
    local frame = brls.AppletFrame.new()
    frame:setHeaderVisibility(brls.Visibility.GONE)
    frame:setFooterVisibility(brls.Visibility.GONE)
    frame:pushContentView(canvas)

    terminal:bindView(canvas)
    terminal:setOverlayBufferText(opts.initialValue or opts.initial or "")
    terminal:setOverlayKeyboardVisible(true)
    terminal:setOnCloseRequest(function()
        if closed then
            return
        end

        closed = true
        if (not submitted) and opts.onCancel then
            pcall(opts.onCancel, terminal:getOverlayBufferText())
        end
        pcall(function()
            brls.Application.popActivity()
        end)
    end)

    if frame.onWillDisappear then
        frame:onWillDisappear(function()
            closed = true
        end)
    end

    brls.Application.pushActivity(frame)

    brls.delay(20, function()
        if closed then
            return
        end

        pcall(function()
            brls.Application.giveFocus(canvas)
        end)
        pcall(function()
            terminal:ensureInputListeners()
        end)
    end)

    return {
        frame = frame,
        canvas = canvas,
        terminal = terminal,
    }
end

return OverlayKeyboardInput
