-- hello_view.lua
local hello_view = {}

function hello_view.init(root)
    print("HelloView: Global activity initialization.")
    local button = root:getView("view_button")
    local button_back = root:getView("close_button")
    print(button)

    if button then
        button:onClick(function(v)
            print("HelloView: view_button clicked")
            brls.Application.notify("HelloView: view_button clicked")
            return true
        end)
    end

    if button_back then
        button_back:onClick(function(v)
            print("HelloView: closing view")
            brls.Application.notify("HelloView: close_button clicked")
            -- brls.Application.popActivity()
            root:dismiss()
            return true
        end)
    end
end

return hello_view