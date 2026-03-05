-- main_activity.lua
local main_activity = {}

local components_tab = require("tab/components_tab")
local settings_tab = require("tab/settings_tab")
local recycling_list_tab = require("tab/recycling_list_tab")
local transform_tab = require("tab/transform_tab")
local text_test_tab = require("tab/text_test_tab")
local game_list_tab = require("tab/game_list_tab")
local cnbeta_list_tab = require("tab/cnbeta_list_tab")
local layout_theme_settings_tab = require("tab/layout_theme_settings_tab")
local hello_tab = require("tab/hello_tab")

-- Global track for current tab
_G.activeTabName = "none"

function main_activity.init(mainView)
    print("MainActivity: Global activity initialization.")
    
    -- Debug: Print all registered views
    print("--- REGISTERED VIEWS START ---")
    local count = 0
    if views then
        for k, v in pairs(views) do
            print("  - " .. tostring(k) .. ": " .. tostring(v))
            count = count + 1
        end
    end
    print("--- REGISTERED VIEWS END: total " .. count .. " ---")
end

function main_activity.show()
    print("MainActivity: Loading main.xml...")

    -- Helper to wrap tab creation and track global session
    local function registerTab(name, xmlPath, initFunc)
        brls.Application.registerXMLView(name, function()
            local tabView = brls.Application.loadXMLRes(xmlPath)
            if tabView then
                _G.activeTabName = name
                
                if initFunc then 
                    if type(initFunc) == "function" then
                        initFunc(tabView) 
                    end
                end
            end
            return tabView
        end)
    end

    -- (1) Register CaptionedImage (Implemented in Lua)
    brls.Application.registerXMLView("CaptionedImage", function()
        local view = brls.Application.loadXMLRes("xml/views/captioned_image.xml")
        if not view then return nil end

        local image = view:getView("image")
        local label = view:getView("label")

        if label then label:setVisibility(brls.Visibility.GONE) end

        -- Forward XML attributes
        view:forwardXMLAttribute("scalingType", image)
        view:forwardXMLAttribute("image", image)
        view:forwardXMLAttribute("focusUp", image)
        view:forwardXMLAttribute("focusRight", image)
        view:forwardXMLAttribute("focusDown", image)
        view:forwardXMLAttribute("focusLeft", image)
        view:forwardXMLAttribute("imageWidth", image, "width")
        view:forwardXMLAttribute("imageHeight", image, "height")
        view:forwardXMLAttribute("caption", label, "text")

        -- Logic: Show caption only when the image is focused
        if image and label then
            image:onFocusGained(function() label:setVisibility(brls.Visibility.VISIBLE) end)
            image:onFocusLost(function() label:setVisibility(brls.Visibility.GONE) end)
        end

        -- Add Tap Gesture
        view:addGestureRecognizer(brls.TapGestureRecognizer.new(view, brls.TapGestureConfig(false, brls.Sound.NONE, brls.Sound.NONE, brls.Sound.NONE)))

        return view
    end)

    -- (2) Register TransformBox (Implemented in Lua with LuaImage)
    brls.Application.registerXMLView("TransformBox", function()
        local view = brls.LuaImage.new()
        
        -- State for transforms (using C++ properties exposed to LuaImage)
        view.rotate_ = 0
        view.skewX_ = 0
        view.skewY_ = 0
        view.scaleX_ = 1
        view.scaleY_ = 1
        view.fontScaleX_ = 1
        view.fontScaleY_ = 1

        -- Methods to match demo API
        view.setRotate = function(s, v) s.rotate_ = v end
        view.setSkewX = function(s, v) s.skewX_ = v end
        view.setSkewY = function(s, v) s.skewY_ = v end
        view.setScaleX = function(s, v) s.scaleX_ = v end
        view.setScaleY = function(s, v) s.scaleY_ = v end
        view.setFontScaleX = function(s, v) s.fontScaleX_ = v end
        view.setFontScaleY = function(s, v) s.fontScaleY_ = v end

        view:setDrawCallback(function(vg, x, y, width, height, style, ctx)
            local centerX = width * math.abs(view.scaleX_) / 2
            local centerY = height * math.abs(view.scaleY_) / 2

            brls.nvgSave(vg)
            brls.nvgTranslate(vg, x + centerX, y + centerY)
            brls.nvgRotate(vg, view.rotate_)
            brls.nvgSkewX(vg, view.skewX_)
            brls.nvgSkewY(vg, view.skewY_)
            brls.nvgScale(vg, view.scaleX_, view.scaleY_)
            
            view:drawBase(vg, -centerX, -centerY, width, height, style, ctx)
            
            brls.nvgTranslate(vg, -centerX, -centerY)
            brls.nvgScale(vg, view.fontScaleX_, view.fontScaleY_)
            brls.nvgText(vg, 4, 18, "demo")
            brls.nvgRestore(vg)
        end)

        return view
    end)

    -- (3) Register other demo views with local initialization
    brls.Application.registerXMLView("PokemonView",      "views/pokemon.xml")
    
    -- Register tabs with the tracking factory
    registerTab("ComponentsTab", "xml/tabs/components.xml", components_tab.init)
    registerTab("TransformTab", "xml/tabs/transform.xml", transform_tab.init)
    registerTab("TextTestTab", "xml/tabs/text_test.xml", text_test_tab.init)
    registerTab("RecyclingListTab", "xml/tabs/recycling_list.xml", recycling_list_tab.init)
    registerTab("GameListTab", "xml/tabs/game_list.xml", game_list_tab.init)
    registerTab("CnBetaListTab", "xml/tabs/cnbeta_list.xml", cnbeta_list_tab.init)
    registerTab("SettingsTab", "xml/tabs/settings.xml", settings_tab.init)
    registerTab("LayoutThemeSettingsTab", "xml/tabs/layout_theme_settings.xml", layout_theme_settings_tab.init)

    registerTab("HelloTab", "xml/tabs/hello.xml", hello_tab.init)

    -- Now load main.xml
    local mainView = brls.Application.loadXMLRes("xml/activity/main.xml")
    if mainView then
        main_activity.init(mainView)
        brls.Application.pushActivity(mainView)
    else
        print("MainActivity: Failed to load xml/activity/main.xml!")
    end
end

return main_activity
