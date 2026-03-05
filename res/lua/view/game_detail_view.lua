-- game_detail_view.lua
local game_detail_view = {}
local image_cache = require("utils/image_cache")

function game_detail_view.init(view, game_data)
    print("Lua: Initializing GameDetailView for " .. (game_data.title or "Unknown"))
    
    -- Get all views
    local thumbnail = view:getView("thumbnail")
    local background_image = view:getView("background_image")
    local overlay = view:getView("overlay")
    local title = view:getView("title")
    local description = view:getView("description")
    local genre = view:getView("genre")
    local platform = view:getView("platform")
    local publisher = view:getView("publisher")
    local developer = view:getView("developer")
    local release_date = view:getView("release_date")
    local play_button = view:getView("play_button")
    local close_button = view:getView("close_button")
    
    -- Set thumbnail and background using image cache (true = no debounce for immediate loading)
    if game_data.thumbnail then
        print("GameDetail: Loading thumbnail: " .. tostring(game_data.thumbnail))
        if thumbnail then
            image_cache.load_image(game_data.thumbnail, thumbnail, "img/game_bg.jpg", true)
        end
        if background_image then
            image_cache.load_image(game_data.thumbnail, background_image, "img/game_bg.jpg", true)
        end
    else
        print("GameDetail: No thumbnail available")
    end
    
    -- Theme-adaptive overlay color
    if overlay then
        local theme = brls.Application.getPlatform():getThemeVariant()
        if theme == brls.ThemeVariant.DARK then
            overlay:setBackgroundColor(brls.nvgRGBA(0, 0, 0, 160))
        else
            overlay:setBackgroundColor(brls.nvgRGBA(255, 255, 255, 160))
        end
    end
    
    -- Theme-adaptive colors
    local theme = brls.Application.getPlatform():getThemeVariant()
    local is_dark = (theme == brls.ThemeVariant.DARK)
    
    -- Neutral but colorful palette
    local color_genre = is_dark and brls.nvgRGBA(0, 188, 212, 255) or brls.nvgRGBA(0, 151, 167, 255)      -- Cyanish
    local color_platform = is_dark and brls.nvgRGBA(76, 175, 80, 255) or brls.nvgRGBA(56, 142, 60, 255)   -- Greenish
    local color_release = is_dark and brls.nvgRGBA(255, 152, 0, 255) or brls.nvgRGBA(230, 81, 0, 255)     -- Orangish
    local color_secondary = is_dark and brls.nvgRGBA(176, 190, 197, 255) or brls.nvgRGBA(84, 110, 122, 255) -- Gray-blue
    local color_text = is_dark and brls.nvgRGBA(236, 240, 241, 255) or brls.nvgRGBA(44, 62, 80, 255)    -- Title/Desc color

    -- Set title
    if title then
        title:setText(game_data.title or "Unknown Game")
        title:setTextColor(color_text)
    end
    
    -- Set description
    if description then
        local desc = tostring(game_data.short_description or "No description available.")
        -- Add full description if available
        if game_data.description then
            desc = tostring(game_data.description)
        end
        description:setText(desc)
        description:setTextColor(color_text)
    end
    
    -- Set genre
    if genre then
        genre:setText(game_data.genre or "Unknown")
        genre:setTextColor(color_genre)
    end
    
    -- Set platform
    if platform then
        platform:setText(game_data.platform or "Unknown")
        platform:setTextColor(color_platform)
    end
    
    -- Set publisher
    if publisher then
        publisher:setText(game_data.publisher or "Unknown")
        publisher:setTextColor(color_secondary)
    end
    
    -- Set developer
    if developer then
        developer:setText(game_data.developer or "Unknown")
        developer:setTextColor(color_secondary)
    end
    
    -- Set release date
    if release_date then
        release_date:setText(game_data.release_date or "Unknown")
        release_date:setTextColor(color_release)
    end
    
    -- Play button - open game URL
    if play_button then
        play_button:onClick(function(v)
            print("Lua: Play button clicked for " .. (game_data.title or "Unknown"))
            
            -- Open game URL if available
            if game_data.game_url then
                print("Lua: Opening URL " .. game_data.game_url)

                local platform = brls.Application.getPlatform()
                if platform and platform.openBrowser then
                    platform:openBrowser(game_data.game_url)
                else
                    print("Lua: Browser not available on this platform")
                end
            end
            
            return true
        end)
    end
    
    -- Close button - dismiss the view
    if close_button then
        close_button:onClick(function(v)
            print("Lua: Closing GameDetailView")
            view:dismiss()
            return true
        end)
    end
    
    
    -- Restore state when leaving
    view:onWillDisappear(function()
        -- Cancel image loads
        if thumbnail then image_cache.cancel_load(thumbnail) end
        if background_image then image_cache.cancel_load(background_image) end
    end)
end

return game_detail_view
