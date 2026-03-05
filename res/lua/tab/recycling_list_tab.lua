-- recycling_list_tab.lua
local recycling_list_tab = {}
local pokemon_view = require("view/pokemon_view")

local pokemons = {
    {id="001", name="Bulbasaur"},
    {id="004", name="Charmander"},
    {id="007", name="Squirtle"},
    {id="011", name="Metapod"},
    {id="014", name="Kakuna"},
    {id="017", name="Pidgeotto"},
    {id="021", name="Spearow"},
    {id="024", name="Arbok"},
    {id="027", name="Sandshrew"}
}

function recycling_list_tab.init(mainView)
    local recycler = mainView:getView("recycler")
    if not recycler then
        print("ERROR: recycler view not found in recycling_list_tab")
        return
    end

    recycler:setEstimatedRowHeight(70)

    -- Register Header cell
    recycler:registerCell("Header", function()
        return brls.RecyclerHeader.create()
    end)

    -- Register Cell - create RecyclerCell from cell.xml
    recycler:registerCell("Cell", function()
        return brls.RecyclerCell.createFromXML("xml/cells/cell.xml")
    end)

    local dataSource = {
        numberOfSections = function(recycler)
            return 200
        end,
        numberOfRows = function(recycler, section)
            return #pokemons
        end,
        titleForHeader = function(recycler, section)
            if section == 0 then return "" end
            return "Section #" .. tostring(section + 1)
        end,
        cellForRow = function(rc, section, row)
            local item = rc:dequeueReusableCell("Cell")
            if item then
                local label = item:getView("title")
                local image = item:getView("image")
                local pokemon = pokemons[row + 1]
                if label then label:setText(pokemon.name) end
                if image then image:setImageFromRes("img/pokemon/thumbnails/" .. pokemon.id .. ".png") end
            end
            return item
        end,
        heightForRow = function(rc, section, row)
            return 70
        end,
        didSelectRowAt = function(rc, section, row)
            local pokemon = pokemons[row + 1]
            print("Lua: Selected " .. pokemon.name)
            
            -- Present PokemonView
            local view = brls.Application.loadXMLRes("xml/views/pokemon.xml")
            if view then
                pokemon_view.init(view, pokemon)
                rc:present(view)
            end
        end
    }

    recycler:setDataSource(dataSource)
end

return recycling_list_tab
