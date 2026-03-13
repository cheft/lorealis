local overlay_keyboard_input = require("overlay_keyboard_input")

local CustomTextInput = {}

local function notifyUnavailable()
    pcall(function()
        brls.Application.notify("系统输入框不可用")
    end)
end

local function valueOr(value, fallback)
    if value == nil or value == "" then
        return fallback
    end
    return value
end

function CustomTextInput.bind(detailCell, imeBridgeCell, opts)
    opts = opts or {}

    local state = {
        value = opts.initialValue or opts.initial or "",
        imeSubmit = nil,
        imeSeeding = false,
    }

    local function refresh()
        if opts.title and detailCell.setText then
            detailCell:setText(opts.title)
        end

        if state.value == "" then
            detailCell:setDetailText(valueOr(opts.placeholder, "点击输入"))
        else
            detailCell:setDetailText(state.value)
        end
    end

    local function emitChange()
        if opts.onChange then
            pcall(opts.onChange, state.value)
        end
    end

    if imeBridgeCell then
        imeBridgeCell:init(
            valueOr(opts.imeTitle, opts.title or "输入"),
            "",
            function(text)
                if state.imeSeeding then
                    return
                end

                state.value = text or ""
                refresh()
                emitChange()

                if state.imeSubmit then
                    local submit = state.imeSubmit
                    state.imeSubmit = nil
                    submit(state.value)
                end
            end,
            "",
            valueOr(opts.imeHint, "支持系统输入法"),
            opts.maxLen or 256
        )
    end

    local function openSystemIme(done)
        if imeBridgeCell then
            state.imeSubmit = done
            state.imeSeeding = true
            imeBridgeCell:setValue(state.value)
            state.imeSeeding = false

            local okOpen, didOpen = pcall(function()
                return imeBridgeCell:openKeyboard(opts.maxLen or 256)
            end)

            if (not okOpen) or didOpen == false then
                state.imeSubmit = nil
                notifyUnavailable()
            end
            return
        end

        local ok = brls.Application.openTextIME(function(text)
            state.value = text or ""
            refresh()
            emitChange()
            if done then
                done(state.value)
            end
        end,
            valueOr(opts.imeTitle, opts.title or "输入"),
            valueOr(opts.imeHint, "支持系统输入法"),
            opts.maxLen or 256,
            state.value,
            0)

        if not ok then
            notifyUnavailable()
        end
    end

    local function openOverlayKeyboard()
        overlay_keyboard_input.open({
            statusText = valueOr(opts.overlayStatusText, opts.title or "自定义输入"),
            initialValue = state.value,
            onRequestSystemIme = function(currentText, resume)
                state.value = currentText or state.value
                refresh()
                emitChange()
                openSystemIme(function(text)
                    if resume then
                        resume(text or "")
                    end
                end)
            end,
            onSubmit = function(text)
                state.value = text or ""
                refresh()
                emitChange()
            end,
        })
    end

    refresh()

    detailCell:onClick(function()
        openOverlayKeyboard()
        return true
    end)

    detailCell:registerAction(
        valueOr(opts.overlayActionLabel, "打开虚拟键盘"),
        brls.ControllerButton.BUTTON_X,
        function()
            openOverlayKeyboard()
            return true
        end
    )

    detailCell:registerAction(
        valueOr(opts.systemActionLabel, "系统输入法"),
        brls.ControllerButton.BUTTON_START,
        function()
            openSystemIme()
            return true
        end
    )

    return {
        getValue = function()
            return state.value
        end,
        setValue = function(value)
            state.value = value or ""
            refresh()
            emitChange()
        end,
        openOverlayKeyboard = openOverlayKeyboard,
        openSystemIme = openSystemIme,
        refresh = refresh,
    }
end

return CustomTextInput
