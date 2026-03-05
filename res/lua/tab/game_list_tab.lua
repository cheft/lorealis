-- game_list_tab.lua
local game_list_tab = {}
local game_detail_view = require("view/game_detail_view")
local network = require("utils/network")
local image_cache = require("utils/image_cache")

-- State tracking
local all_games = {}
local filtered_games = {}
local is_loading = false
local initial_instant_count = 0  -- Count of items allowed to load without debounce

-- API Configuration
local API_URL = "https://www.freetogame.com/api/games"

-- Fetch games from API
local function fetch_games(callback)
    is_loading = true
    print("GameList: Fetching games from API...")
    return network.get(API_URL, function(success, response)
        is_loading = false
        if success and response then
            local json_lib = json or network.json_decode
            local ok, data = pcall(function() 
                if type(json_lib) == "table" and json_lib.decode then
                    return json_lib.decode(response)
                else
                    -- Fallback if global json or json_lib is not a table
                    return network.json_decode(response)
                end
            end)
            
            if ok and data then
                all_games = data
                filtered_games = data
                print("GameList: Loaded " .. #all_games .. " games")
                if callback then callback(true) end
            else
                print("GameList: Error decoding JSON: " .. tostring(data))
                if callback then callback(false) end
            end
        else
            print("GameList: Network error")
            if callback then callback(false) end
        end
    end)
end

-- Refresh the list UI
local function update_recycler(recycler)
    if not recycler then return end
    
    recycler:reloadData()
    
    -- Robust first-screen refresh
    if recycler.invalidate then recycler:invalidate() end
    
    brls.delay(100, function()
        if recycler.invalidate then recycler:invalidate() end
    end)
    
    -- Mark initial load as finished quickly
    brls.delay(100, function()
        initial_instant_count = 10 -- Allow first 10 to be instant, then debounce
    end)
end

-- Initialize the tab view
function game_list_tab.init(view)
    if not view then return end
    
    local recycler = view:getView("recycler")
    local search_bar = view:getView("search_input")
    
    if search_bar then
        search_bar:setOnTextChange(function(text)
            local query = text:lower()
            filtered_games = {}
            for _, game in ipairs(all_games) do
                if (game.title and game.title:lower():find(query)) or 
                   (game.genre and game.genre:lower():find(query)) then
                    table.insert(filtered_games, game)
                end
            end
            update_recycler(recycler)
        end)
    end
    
    if recycler then
        recycler:registerCell("MessageCell", function()
            return brls.RecyclerCell.createFromXML("xml/cells/message_cell.xml")
        end)
        
        recycler:registerCell("GameCell", function()
            local cell = brls.RecyclerCell.createFromXML("xml/cells/game_cell.xml")
            if cell.setPrepareForReuseCallback then
                cell:setPrepareForReuseCallback(function()
                    local thumbnail = cell:getView("thumbnail")
                    if thumbnail then
                        print(string.format("GameList: [REUSE] View %s", tostring(thumbnail)))
                        image_cache.cancel_load(thumbnail)
                    end
                end)
            end
            
            -- CRITICAL: Also cancel when cell is hidden but not yet reused
            if cell.onWillDisappear then
                cell:onWillDisappear(function()
                    local thumbnail = cell:getView("thumbnail")
                    if thumbnail then
                        print(string.format("GameList: [HIDE] View %s", tostring(thumbnail)))
                        image_cache.cancel_load(thumbnail)
                    end
                end)
            end
            return cell
        end)
        
        local dataSource = {
            numberOfSections = function() return 1 end,
            numberOfRows = function() 
                if is_loading then return 1 end
                if #filtered_games == 0 then return 1 end
                return #filtered_games 
            end,
            cellForRow = function(rc, section, row)
                if is_loading then
                    local cell = rc:dequeueReusableCell("MessageCell")
                    local label = cell:getView("message_label")
                    if label then label:setText("Loading...") end
                    return cell
                end
                
                if #filtered_games == 0 then
                    local cell = rc:dequeueReusableCell("MessageCell")
                    local label = cell:getView("message_label")
                    if label then label:setText("No results found.") end
                    return cell
                end
                
                local cell = rc:dequeueReusableCell("GameCell")
                if not cell then return nil end
                
                local game = filtered_games[row + 1]
                if game then
                    local title = cell:getView("title")
                    local desc = cell:getView("description")
                    local genre = cell:getView("genre")
                    local platform = cell:getView("platform")
                    local thumbnail = cell:getView("thumbnail")
                    
                    if title then title:setText(game.title or "Unknown") end
                    if desc then 
                        local d = tostring(game.short_description or "")
                        if #d > 80 then d = d:sub(1, 77) .. "..." end
                        desc:setText(d) 
                    end
                    if genre then genre:setText(game.genre or "") end
                    if platform then platform:setText(game.platform or "") end
                    
                    if thumbnail and game.thumbnail then
                        local should_instant = (row < 10)
                        image_cache.load_image(game.thumbnail, thumbnail, "img/game_bg.jpg", should_instant)
                    end
                end
                return cell
            end,
            heightForRow = function(rc, section, row) return 100 end,
            didSelectRowAt = function(rc, section, row)
                if is_loading or #filtered_games == 0 then return end
                local game = filtered_games[row + 1]
                if game then
                    local detail = brls.Application.loadXMLRes("xml/views/game_detail.xml")
                    if detail then
                        game_detail_view.init(detail, game)
                        rc:present(detail)
                    end
                end
            end
        }
        
        recycler:setDataSource(dataSource)
        
        -- Initial load
        local rid = fetch_games(function(success)
            update_recycler(recycler)
        end)
        
        -- Cleanup on tab switch
        view:onWillDisappear(function()
            if rid then
                print("GameList: Tab disappearing, cancelling API request")
                network.cancel(rid)
                rid = nil
            end
        end)
    end
end

return game_list_tab
