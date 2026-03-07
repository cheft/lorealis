-- hello_tab.lua
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
    -- for i = 1, 3 do
    --     local button = brls.Button.new(
    --         "Button " .. i,
    --         function(v)
    --             print("Button " .. i .. " clicked")
    --             return true
    --         end
    --     )
    --     hello_box:addView(button)
    -- end

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

    -- Add Fetch Website HTML Button
    local fetch_website_btn = brls.Button.new(
        "Fetch Website HTML",
        function(v)
            local dialog = brls.Dialog.new("Fetch Website HTML")
            local input = brls.InputCell.new()
            input:init("URL", "https://thebookofshaders.com/?lan=ch", function(text) end, "https://thebookofshaders.com/?lan=ch", "Enter full URL", 256)
            dialog:addView(input)
            
            dialog:addButton("Fetch", function()
                local url = input:getValue()
                if url == "" then return end
                
                brls.Application.notify("Fetching " .. url .. "...")
                brls.Network.get(url, function(success, statusCode, response)
                    -- Detect Cloudflare challenge from response content
                    local is_challenge = false
                    if success and response then
                        if response:find("<title>Just a moment...</title>") or 
                           response:find("cf-browser-verification") or
                           response:find("cf-challenge") then
                            is_challenge = true
                        end
                    end

                    if success and not is_challenge then
                        local content = brls.ScrollingFrame.new()
                        local renderer = brls.HtmlRenderer.new()
                        renderer:renderString(response)
                        renderer:setPadding(64)
                        content:setContentView(renderer)
                        v:present(content)
                    else
                        local errorMsg = ""
                        if is_challenge then
                            errorMsg = "Blocked by Cloudflare protection"
                        else
                            errorMsg = "Status: " .. tostring(statusCode)
                            if statusCode < 0 then
                                local winErr = -statusCode
                                if winErr == 12007 then errorMsg = "DNS Error (12007)"
                                elseif winErr == 12029 then errorMsg = "Connection Refused (12029)"
                                elseif winErr == 12002 then errorMsg = "Timeout (12002)"
                                elseif winErr == 12157 then errorMsg = "SSL/TLS Error (12157)"
                                else errorMsg = "WinInet Error " .. tostring(winErr)
                                end
                            end
                        end
                        brls.Application.notify("Failed to fetch: " .. errorMsg)
                        print("Fetch Error: URL=" .. url .. " " .. errorMsg)
                    end
                end)
            end)
            
            dialog:addButton("Cancel", function()
                dialog:close()
            end)
            
            dialog:open()
            return true
        end
    )
    hello_box:addView(fetch_website_btn)

    -- Add SSH Client Button
    local ssh_btn = brls.Button.new(
        "SSH Client",
        function(v)
            print("HelloTab: SSH Client clicked")
            -- Load SSH module main.lua
            local ssh_main = dofile("mod/ssh/lua/main.lua")
            if ssh_main and ssh_main.show then
                ssh_main.show()
            else
                brls.Application.notify("Failed to load SSH module")
            end
            return true
        end
    )
    hello_box:addView(ssh_btn)

    if button then
        button:onClick(function(v)
            print("HelloTab: button clicked")
            -- 每次重新创建 view，避免 popActivity() 后旧指针悬空导致闪退
            local view, mod = zip_loader.load("hello.blpkg", "main.xml", "main.lua")
            if view and mod then
                mod.init(view)          -- 初始化事件绑定
                v:present(view)
            end
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