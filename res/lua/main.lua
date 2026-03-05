-- main.lua
print("BRLS: main.lua (Orchestrator) starting...")

local main_activity = require("activity/main_activity")

-- Global initialization function called by C++ main.cpp
function onInit()
    print("main.lua: onInit() called")

    -- Window and App Initialization
    brls.Application.createWindow("NS Dashboard")
    
    -- Load Windows Emoji font as fallback (safely after window creation)
    -- On Switch/other platforms this path won't exist but loadFontFromFile handles it.
    brls.Application.loadFontFromFile("emoji", "C:\\Windows\\Fonts\\seguiemj.ttf")
    
    -- Register emoji fallback for all main fonts
    brls.Application.addFontFallback("regular", "emoji")
    brls.Application.addFontFallback("zh-Hans", "emoji")
    brls.Application.addFontFallback("zh-Hant", "emoji")
    brls.Application.addFontFallback("korean", "emoji")
    -- brls.Application.getPlatform():setThemeVariant(brls.ThemeVariant.LIGHT)
    brls.Application.setGlobalQuit(false)
    
    -- Custom Theme Colors
    brls.Theme.getLightTheme():addColor("captioned_image/caption", brls.nvgRGB(2, 176, 183))
    brls.Theme.getDarkTheme():addColor("captioned_image/caption", brls.nvgRGB(51, 186, 227))

    -- Custom Style Metrics
    brls.getStyle():addMetric("about/padding_top_bottom", 50)
    brls.getStyle():addMetric("about/padding_sides", 75)
    brls.getStyle():addMetric("about/description_margin", 50)

    -- Initialize the main activity and its tabs
    main_activity.show()

    -- Globally disable header and footer using standard API
    local applet = brls.Application.getAppletFrame()
    if applet then
        print("Lua: Hiding AppletFrame header and footer globally")
        applet:setHeaderVisibility(brls.Visibility.GONE)
        applet:setFooterVisibility(brls.Visibility.GONE)
    end


    print("main.lua: initialization finished.")
end

-- Re-setup things from old main.lua if needed
print("BRLS: main.lua loaded.")
