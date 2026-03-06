-- main.lua
print("BRLS: main.lua (Orchestrator) starting...")

local main_activity = require("activity/main_activity")

-- Global initialization function called by C++ main.cpp
function onInit()
    print("main.lua: onInit() called")

    -- Window and App Initialization
    print("main.lua: [1/7] Creating window...")
    brls.Application.createWindow("NS Dashboard")
    print("main.lua: [2/7] Window created OK")
    
    -- Load Windows Emoji font as fallback (only on Desktop/Windows)
    -- On Switch, this path doesn't exist and could waste time or cause issues
    local platform = brls.Application.getPlatform()
    local platformName = platform and platform:getName() or "unknown"
    print("main.lua: Platform = " .. tostring(platformName))
    
    if platformName ~= "Switch" then
        print("main.lua: [3/7] Loading emoji font (Desktop only)...")
        brls.Application.loadFontFromFile("emoji", "C:\\Windows\\Fonts\\seguiemj.ttf")
        
        -- Register emoji fallback for all main fonts
        brls.Application.addFontFallback("regular", "emoji")
        brls.Application.addFontFallback("zh-Hans", "emoji")
        brls.Application.addFontFallback("zh-Hant", "emoji")
        brls.Application.addFontFallback("korean", "emoji")
        print("main.lua: [3/7] Emoji font loaded OK")
    else
        print("main.lua: [3/7] Skipping emoji font (Switch platform)")
    end

    print("main.lua: [4/7] Configuring app settings...")
    brls.Application.setGlobalQuit(false)
    
    -- Custom Theme Colors
    brls.Theme.getLightTheme():addColor("captioned_image/caption", brls.nvgRGB(2, 176, 183))
    brls.Theme.getDarkTheme():addColor("captioned_image/caption", brls.nvgRGB(51, 186, 227))

    -- Custom Style Metrics
    brls.getStyle():addMetric("about/padding_top_bottom", 50)
    brls.getStyle():addMetric("about/padding_sides", 75)
    brls.getStyle():addMetric("about/description_margin", 50)
    print("main.lua: [5/7] Theme and style configured OK")

    -- Initialize the main activity and its tabs
    print("main.lua: [6/7] Showing main activity...")
    main_activity.show()
    print("main.lua: [6/7] Main activity shown OK")

    -- Globally disable header and footer using standard API
    print("main.lua: [7/7] Configuring AppletFrame...")
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

