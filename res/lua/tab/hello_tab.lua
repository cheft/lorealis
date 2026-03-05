-- hello_tab.lua
local hello_view = require("view/hello_view")
local zip_loader = require("utils/zip_view_loader")

local hello_tab = {}
local selected = 0

function hello_tab.init(mainView)
    print("HelloTab: Global activity initialization.")
    local button = mainView:getView("hello_button")
    local label = mainView:getView("hello_label")
    local hello_box = mainView:getView("hello_box")

    -- 注意: 不要在这里预先创建 view，因为 popActivity 后 Borealis 会释放它
    -- 每次按钮点击时重新创建，见下方 onClick 回调

    -- loop render 10 Buttons
    for i = 1, 3 do
        local button = brls.Button.new(
            "Button " .. i,
            function(v)
                print("Button " .. i .. " clicked")
                return true
            end
        )
        hello_box:addView(button)
    end

    -- Add HTML Renderer Test Button
    local test_html_btn = brls.Button.new(
        "Test HTML Renderer",
        function(v)
            print("HelloTab: HTML test clicked")
            local html_test = require("html_test")
            local renderer = html_test.html()
            v:present(renderer)
            return true
        end
    )
    hello_box:addView(test_html_btn)

    -- Add Markdown Renderer Test Button
    local test_markdown_btn = brls.Button.new(
        "Test Markdown Renderer",
        function(v)
            print("HelloTab: Markdown test clicked")
            local html_test = require("html_test")
            local renderer = html_test.markdown()
            v:present(renderer)
            return true
        end
    )
    hello_box:addView(test_markdown_btn)

    if button then
        button:onClick(function(v)
            print("HelloTab: button clicked")

             -- 每次重新创建 view，避免 popActivity() 后旧指针悬空导致闪退
            -- local view, mod = zip_loader.load("hello_view.blpkg", "main.xml", "main.lua")
            -- if view and mod then
            --     mod.init(view)          -- 初始化事件绑定
            --     brls.Application.pushActivity(view)  -- 打开页面
            -- end
           
            local view = brls.Application.loadXMLRes("xml/views/hello.xml")
            hello_view.init(view)          -- 初始化事件绑定
            v:present(view)  -- 使用 present 替代 pushActivity 以获得更顺滑的动画

            -- local dropdown = brls.Dropdown.new(
            --     "Test",
            --     {
            --         "Test 1", "Test 2", "Test 3", "Test 4", "Test 5",
            --         "Test 6", "Test 7", "Test 8", "Test 9", "Test 10",
            --         "Test 11", "Test 12", "Test 13"
            --     },
            --     function(_selected)
            --         selected = _selected
            --         print("HelloTab: Dropdown selected: " .. tostring(_selected))
            --         label:setText("Selected: " .. tostring(_selected))
            --     end,
            --     selected
            -- )
            -- brls.Application.pushActivity(dropdown)
            return true
        end)
    end
end


function hello_tab.onClick(mainView)
    print("HelloTab: onClick")
end

function hello_tab.onUnfocus(mainView)
    print("HelloTab: onUnfocus")
end

return hello_tab