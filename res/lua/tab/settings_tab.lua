local settings_tab = {}

local radioSelected = false
local NOTIFICATIONS = {
    "You have cool hair",
    "I like your shoes",
    "borealis is powered by nanovg",
    "The Triforce is an inside job",
    "Pozznx will trigger in one day and twelve hours",
    "Aurora Borealis? At this time of day, at this time of year, in this part of the gaming market, located entirely within your Switch?!",
    "May I see it?",
    "Hmm, Steamed Hams!",
    "Hello\nWorld!"
}

function settings_tab.init(mainView)
    if not mainView then return end
    
    -- Bind views
    local radio = mainView:getView("radio")
    local boolean = mainView:getView("boolean")
    local selector = mainView:getView("selector")
    local input = mainView:getView("input")
    local inputNumeric = mainView:getView("inputNumeric")
    local ipAddress = mainView:getView("ipAddress")
    local dnsServer = mainView:getView("dnsServer")
    local debugCell = mainView:getView("debug")
    local screenSaver = mainView:getView("screenSaver")
    local bottomBar = mainView:getView("bottomBar")
    local alwaysOnTop = mainView:getView("alwaysOnTop")
    local fps = mainView:getView("fps")
    local swapInterval = mainView:getView("swapInterval")
    local brightnessSlider = mainView:getView("brightnessSlider")
    local notify = mainView:getView("notify")
    local themeSwitcher = mainView:getView("themeSwitcher")
    local platform = brls.Application.getPlatform()

    -- 0. Theme Switcher
    if themeSwitcher and platform then
        local currentTheme = platform:getThemeVariant()
        themeSwitcher:init("Theme", currentTheme == brls.ThemeVariant.DARK, function(value)
            local newTheme = value and brls.ThemeVariant.DARK or brls.ThemeVariant.LIGHT
            platform:setThemeVariant(newTheme)
            brls.Application.notify("Switched to " .. (value and "dark" or "light") .. " theme")
        end)
    end

    -- 1. Radio cell
    if radio then
        if radio.title then radio.title:setText("Radio cell") end
        radio:setSelected(radioSelected)
        radio:onClick(function()
            radioSelected = not radioSelected
            radio:setSelected(radioSelected)
            return true
        end)
    end

    -- 2. Switcher (BooleanCell)
    if boolean then
        if boolean.title then boolean.title:setText("Switcher") end
    end

    -- 3. Debug Layer
    if debugCell then
        debugCell:init("Debug Layer", brls.Application.isDebuggingViewEnabled(), function(value)
            brls.Application.enableDebuggingView(value)
            brls.Application.notify((value and "Open" or "Close") .. " the debug layer")
        end)
    end

    -- 4. ScreenSaver
    local platform = brls.Application.getPlatform()
    if screenSaver and platform then
        screenSaver:init("Disable ScreenSaver", platform:isScreenDimmingDisabled(), function(value)
            platform:disableScreenDimming(value)
        end)
    end

    -- 5. Bottom Bar
    if bottomBar then
        local isHidden = brls.getHideBottomBar()
        bottomBar:init("Bottom Bar", isHidden, function(value)
            brls.setHideBottomBar(value)
            local stack = brls.Application.getActivitiesStack()
            for i = 1, #stack do
                local activity = stack[i]
                local frame = activity:getContentView()
                if frame and frame.setFooterVisibility then
                    frame:setFooterVisibility(not value and brls.Visibility.GONE or brls.Visibility.VISIBLE)
                end
            end
        end)
    end

    -- 6. FPS
    if fps then
        fps:init("FPS", brls.Application.getFPSStatus(), function(value)
            brls.Application.setFPSStatus(value)
        end)
    end

    -- 7. Swap Interval
    if swapInterval then
        swapInterval:init("Swap Interval", {"0", "1", "2", "3", "4"}, 1, function(selected) end, function(selected)
            brls.Application.setSwapInterval(selected)
        end)
    end

    -- 8. Always On Top
    if alwaysOnTop and platform then
        alwaysOnTop:init("Always On Top", false, function(value)
            platform:setWindowAlwaysOnTop(value)
        end)
    end

    -- 9. Selector
    if selector then
        selector:init("Selector", { "Test 1", "Test 2", "Test 3", "Test 4", "Test 5", "Test 6", "Test 7", "Test 8", "Test 9", "Test 10", "Test 11", "Test 12", "Test 13" }, 0, 
        function(selected) end,
        function(selected)
            local dialog = brls.Dialog.new("selected " .. tostring(selected))
            dialog:addButton(brls.i18n("hints/ok"), function() 
                -- Do NOT call dialog:close() here, brls::Dialog handles it automatically
                return true
            end)
            dialog:open()
        end)
    end

    -- 10. Input text (with action)
    if input then
        input:init("Input text", "https://github.com", function(text) end, "Placeholder", "Hint")
        input:registerAction(brls.i18n("hints/open"), brls.ControllerButton.BUTTON_X, function(view)
            -- DetailCell inherits .detail label from RecyclerCell/Box hierarchy
            if platform and input.detail then
                platform:openBrowser(input.detail:getFullText())
            end
            return true
        end)
    end

    -- 11. Input numeric
    if inputNumeric then
        inputNumeric:init("Input number", 2448, function(number) end, "Hint")
    end

    -- 12. IP & DNS
    if ipAddress and platform then
        ipAddress:setDetailText(platform:getIpAddress())
    end
    if dnsServer and platform then
        dnsServer:setDetailText(platform:getDnsServer())
    end

    -- 13. Brightness Slider
    if brightnessSlider and platform then
        local brightness = platform:getBacklightBrightness()
        brightnessSlider:init("Brightness", brightness, function(value)
            platform:setBacklightBrightness(value)
            brightnessSlider:setDetailText(string.format("%.2f", value))
        end)
        brightnessSlider:setDetailText(string.format("%.2f", brightness))
    end

    -- 14. Notification Trigger
    if notify then
        notify:onClick(function()
            local msg = NOTIFICATIONS[math.random(#NOTIFICATIONS)]
            brls.Application.notify(msg)
            return true
        end)
    end
    
end

return settings_tab

