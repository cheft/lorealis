-- pokemon_view.lua
local pokemon_view = {}

function pokemon_view.init(view, pokemon_data)
    print("Lua: Initializing PokemonView for " .. pokemon_data.name)
    
    local image = view:getView("image")
    local description = view:getView("description")
    local close_button = view:getView("close_button")

    if image then
        image:setImageFromRes("img/pokemon/" .. pokemon_data.id .. ".png")
    end

    if description then
        description:setText("It's a pokemon with name: " .. pokemon_data.name .. "\n(Business logic handled by Lua)")
    end

    if close_button then
        close_button:onClick(function(v)
            print("Lua: Dismissing PokemonView")
            -- Dismiss the presented view
            view:dismiss()
            return true
        end)
    end
end

return pokemon_view
