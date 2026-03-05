-- transform_tab.lua
local transform_tab = {}

function transform_tab.init(mainView)
    if not mainView then return end

    local activeAnimations = {}

    local function stopAnimations()
        for _, ani in ipairs(activeAnimations) do
            pcall(function() 
                ani:setTickCallback(nil)
                ani:stop() 
            end)
        end
        activeAnimations = {}
    end

    -- Robust cleanup on tab switch using the new willDisappear event
    mainView:onWillDisappear(function()
        stopAnimations()
    end)

    local box = mainView:getView("box")
    local play = mainView:getView("play")
    local reset = mainView:getView("reset")

    local transX = mainView:getView("transX")
    local transY = mainView:getView("transY")
    local scaleX = mainView:getView("scaleX")
    local scaleY = mainView:getView("scaleY")
    local skewX = mainView:getView("skewX")
    local skewY = mainView:getView("skewY")
    local rotate = mainView:getView("rotate")
    local boxWidth = mainView:getView("width")
    local boxHeight = mainView:getView("height")
    local fontScaleX = mainView:getView("fontScaleX")
    local fontScaleY = mainView:getView("fontScaleY")

    local POINTER_SIZE = 20
    local BOX_SIZE = 100
    local CONTAINER_SIZE = 400
    local ANIMATION = 4000

    -- Helper to wire up slider cells
    local function setupSlider(cell, initial, cb)
        if not cell then return end
        local res = cb(initial)
        cell:setDetailText(string.format("%.2f", res))
        local slider = cell:getSlider()
        if slider then slider:setPointerSize(POINTER_SIZE) end
        cell:init(cell:getId(), initial, function(v)
            cb(v)
            cell:setDetailText(string.format("%.2f", v))
        end)
    end

    if play then
        play:onClick(function(v)
            stopAnimations()
            
            local aniX = brls.Animatable.new()
            local aniY = brls.Animatable.new()
            local skew_ani = brls.Animatable.new()
            local skew2_ani = brls.Animatable.new()
            table.insert(activeAnimations, aniX)
            table.insert(activeAnimations, aniY)
            table.insert(activeAnimations, skew_ani)
            table.insert(activeAnimations, skew2_ani)

            aniX:reset(0)
            aniX:addStep(1.0, ANIMATION, brls.EasingFunction.exponentialOut)
            aniX:addStep(0.0, ANIMATION, brls.EasingFunction.cubicIn)
            aniX:addStep(0.5, ANIMATION, brls.EasingFunction.exponentialOut)
            aniX:addStep(0.0, ANIMATION, brls.EasingFunction.cubicIn)
            aniX:setTickCallback(function()
                pcall(function()
                    if transX then
                        local slider = transX:getSlider()
                        if slider then slider:setProgress(aniX:getProgress()) end
                    end
                end)
            end)

            aniY:reset(0)
            aniY:addStep(1.0, ANIMATION, brls.EasingFunction.bounceOut)
            aniY:addStep(0.0, ANIMATION, brls.EasingFunction.cubicIn)
            aniY:addStep(1.0, ANIMATION, brls.EasingFunction.bounceOut)
            aniY:addStep(0.0, ANIMATION, brls.EasingFunction.cubicIn)
            aniY:setTickCallback(function()
                pcall(function()
                    if transY then
                        local slider = transY:getSlider()
                        if slider then slider:setProgress(aniY:getProgress()) end
                    end
                end)
            end)

            skew_ani:reset(0)
            skew_ani:addStep(1.0, ANIMATION, brls.EasingFunction.bounceOut)
            skew_ani:addStep(0.0, ANIMATION, brls.EasingFunction.cubicIn)
            skew_ani:setTickCallback(function()
                pcall(function()
                    local progress = skew_ani:getProgress()
                    if skewY then
                        local slider = skewY:getSlider()
                        if slider then slider:setProgress(progress) end
                    end
                    if scaleX then
                        local slider = scaleX:getSlider()
                        if slider then slider:setProgress(1.0 - progress) end
                    end
                end)
            end)

            skew2_ani:reset(0)
            skew2_ani:addStep(0.0, ANIMATION * 2, brls.EasingFunction.linear)
            skew2_ani:addStep(1.0, ANIMATION, brls.EasingFunction.bounceOut)
            skew2_ani:addStep(0.0, ANIMATION, brls.EasingFunction.cubicIn)
            skew2_ani:setTickCallback(function()
                pcall(function()
                    local progress = skew2_ani:getProgress()
                    if skewX then
                        local slider = skewX:getSlider()
                        if slider then slider:setProgress(progress) end
                    end
                    if scaleY then
                        local slider = scaleY:getSlider()
                        if slider then slider:setProgress(1.0 - progress) end
                    end
                end)
            end)

            aniX:start()
            aniY:start()
            skew_ani:start()
            skew2_ani:start()
            return true
        end)
    end

    if reset then
        reset:onClick(function(v)
            stopAnimations()
            if transX then
                local slider = transX:getSlider()
                if slider then slider:setProgress(0) end
            end
            if transY then
                local slider = transY:getSlider()
                if slider then slider:setProgress(0) end
            end
            if scaleX then
                local slider = scaleX:getSlider()
                if slider then slider:setProgress(1) end
            end
            if scaleY then
                local slider = scaleY:getSlider()
                if slider then slider:setProgress(1) end
            end
            if skewX then
                local slider = skewX:getSlider()
                if slider then slider:setProgress(0) end
            end
            if skewY then
                local slider = skewY:getSlider()
                if slider then slider:setProgress(0) end
            end
            if rotate then
                local slider = rotate:getSlider()
                if slider then slider:setProgress(0) end
            end
            if boxWidth then
                local slider = boxWidth:getSlider()
                if slider then slider:setProgress(1) end
            end
            if boxHeight then
                local slider = boxHeight:getSlider()
                if slider then slider:setProgress(1) end
            end
            if fontScaleX then
                local slider = fontScaleX:getSlider()
                if slider then slider:setProgress(1) end
            end
            if fontScaleY then
                local slider = fontScaleY:getSlider()
                if slider then slider:setProgress(1) end
            end
            return true
        end)
    end

    setupSlider(transX, 0, function(v) 
        if box then box:setTranslationX((CONTAINER_SIZE - BOX_SIZE) * v) end return v 
    end)
    setupSlider(transY, 0, function(v) 
        if box then box:setTranslationY((CONTAINER_SIZE - BOX_SIZE) * v) end return v 
    end)
    setupSlider(scaleX, 1, function(v) 
        local scale = v * 2 - 1
        if box then box:setScaleX(scale) end return scale 
    end)
    setupSlider(scaleY, 1, function(v) 
        local scale = v * 2 - 1
        if box then box:setScaleY(scale) end return scale 
    end)
    setupSlider(skewX, 0, function(v) 
        if box then box:setSkewX(v * math.pi) end return v 
    end)
    setupSlider(skewY, 0, function(v) 
        if box then box:setSkewY(v * math.pi) end return v 
    end)
    setupSlider(rotate, 0, function(v) 
        if box then box:setRotate(v * math.pi * 2) end return v 
    end)
    setupSlider(boxWidth, 1, function(v) 
        if box then box:setWidth(v * BOX_SIZE) end 
        return v
    end)
    setupSlider(boxHeight, 1, function(v) 
        if box then box:setHeight(v * BOX_SIZE) end 
        return v
    end)
    setupSlider(fontScaleX, 1, function(v) 
        local scale = v * 2 - 1
        if box then box:setFontScaleX(scale) end return scale 
    end)
    setupSlider(fontScaleY, 1, function(v)
        local scale = v * 2 - 1
        if box then box:setFontScaleY(scale) end return scale
    end)
    
    print("TransformTab: initialized")
end

function transform_tab.deinit()
end

return transform_tab
