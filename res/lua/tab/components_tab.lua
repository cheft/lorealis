-- components_tab.lua
-- Mirrors ComponentsTab.cpp logic from the original Borealis demo
local components_tab = {}

-- Persistent selection state (matches `int selected = 0;` in C++)
local selected = 0

function components_tab.init(mainView)
    -- button_primary: opens a Dropdown and remembers last selection
    local button_primary = mainView:getView("button_primary")
    local button_bordered = mainView:getView("button_bordered")
    local button_highlight = mainView:getView("button_highlight")

    if button_primary then
        button_primary:onClick(function(v)
            local dropdown = brls.Dropdown.new(
                "Test",
                {
                    "Test 1", "Test 2", "Test 3", "Test 4", "Test 5",
                    "Test 6", "Test 7", "Test 8", "Test 9", "Test 10",
                    "Test 11", "Test 12", "Test 13"
                },
                function(_selected)
                    selected = _selected
                end,
                selected
            )
            brls.Application.pushActivity(dropdown)
            return true
        end)
    else
        print("ComponentsTab: button_primary not found in views!")
    end

    -- button_highlight: registers a "Honk" action on BUTTON_A
    if button_highlight then
        button_highlight:registerAction(
            "Honk",
            brls.ControllerButton.BUTTON_A,
            function(v)
                return true
            end
        )
    else
        print("ComponentsTab: button_highlight not found in views!")
    end

    -- slider + progress label: update label text on slider change
    local progress = mainView:getView("progress")
    local slider   = mainView:getView("slider")
    if slider and progress then
        progress:setText(tostring(math.floor(slider:getProgress() * 100)))
        slider:onProgressChange(function(p)
            progress:setText(tostring(math.floor(p * 100)))
        end)
    else
        print("ComponentsTab: slider or progress not found in views! slider=" ..
              tostring(slider) .. " progress=" .. tostring(progress))
    end
end

return components_tab
