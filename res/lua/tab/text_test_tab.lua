-- text_test_tab.lua
local text_test_tab = {}

function text_test_tab.init(mainView)
    local label = mainView:getView("label")
    local width_slider = mainView:getView("width")
    local height_slider = mainView:getView("height")
    local horizontal = mainView:getView("horizontal")
    local vertical = mainView:getView("vertical")
    local single_line = mainView:getView("singleLine")

    local function updateSlider(cell, init, title, cb)
        if not cell then return end
        local val = cb(init)
        cell:setDetailText(val <= 0 and "auto" or string.format("%d", math.floor(val)))
        local slider = cell:getSlider()
        if slider then slider:setPointerSize(20) end
        cell:init(title, init, function(v)
            local res = cb(v)
            cell:setDetailText(res <= 0 and "auto" or string.format("%d", math.floor(res)))
        end)
    end

    if label then
        updateSlider(width_slider, 1.0, "width", function(v)
            local w = v * 400
            label:setWidth(w <= 0 and -1 or w)
            return w
        end)

        updateSlider(height_slider, 0.0, "height", function(v)
            local h = v * 400
            if single_line then
                single_line:setVisibility(h <= 0 and brls.Visibility.VISIBLE or brls.Visibility.GONE)
            end
            label:setHeight(h <= 0 and -1 or h)
            return h
        end)

        if horizontal then
            horizontal:init("horizontalAlign", { "left", "center", "right" }, 0, function(h) end, function(s)
                label:setHorizontalAlign(s)
            end)
        end

        if vertical then
            vertical:init("verticalAlign", { "baseline", "top", "center", "bottom" }, 2, function(h) end, function(s)
                label:setVerticalAlign(s)
            end)
        end

        if single_line then
            single_line:init("singleLine", false, function(v)
                label:setSingleLine(v)
            end)
        end
    end
end

return text_test_tab
