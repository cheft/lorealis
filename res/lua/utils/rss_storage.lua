-- rss_storage.lua - RSS Sources persistence utility
local rss_storage = {}

-- Default RSS sources (used when no saved file exists)
local DEFAULT_RSS_SOURCES = {
    {
        id = "gcores",
        name = "机核 GCORES",
        url = "https://www.gcores.com/rss",
    },
    {
        id = "ifanr",
        name = "爱范儿",
        url = "https://www.ifanr.com/feed",
    },
    {
        id = "mac52ipod",
        name = "苹果fans博客",
        url = "https://www.mac52ipod.cn/feed.php",
    },
    {
        id = "cnbeta",
        name = "cnBeta",
        url = "https://rss.cnbeta.com.tw/",
    },
    {
        id = "itchio",
        name = "itchio",
        url = "https://itch.io/games.xml",
    },
    {
        id = "nintendo",
        name = "Nintendo News",
        url = "https://mynintendonews.com/feed/",
    },
    {
        id = "xbox",
        name = "Xbox News",
        url = "https://news.xbox.com/en-us/feed/",
    },
    {
        id = "playstation",
        name = "Playstation News",
        url = "https://blog.playstation.com/feed/",
    },
    { id="steam", name = "Steam News", url = "https://store.steampowered.com/feeds/news.xml"},
    { id="steamFeatured", name = "Steam Featured", url = "https://store.steampowered.com/feeds/news/collection/featured/"},
    { id="ign", name = "IGN", url = "https://www.ign.com/rss/articles"},
    { id="gameSpot", name = "GameSpot", url = "https://www.gamespot.com/feeds/news"},
    { id="eurogamer", name = "Eurogamer", url = "https://www.eurogamer.net/rss"},
    { id="kotaku", name = "Kotaku", url = "https://kotaku.com/rss"},
    { id="polygon", name = "Polygon", url = "https://www.polygon.com/rss/index.xml"},
    { id="verge", name = "Verge", url = "https://www.theverge.com/rss/index.xml"},
    { id="techCrunch", name = "TechCrunch", url = "https://techcrunch.com/feed"}
}

-- Get platform-specific storage path
local function get_storage_path()
    local platform = brls.Application.getPlatform()
    if not platform then
        return "rss_sources.json"
    end
    
    -- Check platform name
    if platform.getName then
        local name = platform:getName()
        if name and name:lower():find("switch") then
            return "sdmc:/switch/ns_dashboard/rss_sources.json"
        end
    end
    
    -- Default to Windows/Desktop data directory
    return "data/rss_sources.json"
end

-- STORAGE_FILE is now determined dynamically in each function
-- to ensure platform is initialized when called

-- Generate a simple ID from name
local function generate_id(name)
    if not name or name == "" then
        return "rss_" .. tostring(os.time())
    end
    -- Convert to lowercase, replace spaces with underscores
    local id = name:lower():gsub("%s+", "_"):gsub("[^%w_]", "")
    -- Add timestamp to ensure uniqueness
    return id .. "_" .. tostring(os.time() % 10000)
end

-- Check if platform supports file operations
local function is_storage_available()
    local platform = brls.Application.getPlatform()
    if not platform then
        print("RSSStorage: Platform not available")
        return false
    end
    local has_read = platform.readFile ~= nil
    local has_write = platform.writeFile ~= nil
    print("RSSStorage: Platform readFile=" .. tostring(has_read) .. ", writeFile=" .. tostring(has_write))
    return has_read and has_write
end

-- Load RSS sources from disk
function rss_storage.load()
    if not is_storage_available() then
        print("RSSStorage: Platform doesn't support file storage, using defaults")
        return DEFAULT_RSS_SOURCES
    end

    local platform = brls.Application.getPlatform()
    local storage_path = get_storage_path()
    print("RSSStorage: Loading from " .. storage_path)
    local content = platform:readFile(storage_path)
    if not content or content == "" then
        print("RSSStorage: No saved file found at " .. storage_path .. ", using defaults")
        return DEFAULT_RSS_SOURCES
    end

    -- Try to parse JSON
    local ok, sources = pcall(function()
        -- Simple JSON parsing - assumes format: [{"id":"x","name":"y","url":"z"},...]
        local result = {}
        -- Remove outer brackets
        content = content:gsub("^%s*%[", ""):gsub("%]%s*$", "")
        
        -- Split by "},{" to get individual objects
        for obj in content:gmatch("%b{}") do
            local item = {}
            -- Extract fields
            item.id = obj:match('"id"%s*:%s*"([^"]+)"')
            item.name = obj:match('"name"%s*:%s*"([^"]+)"')
            item.url = obj:match('"url"%s*:%s*"([^"]+)"')
            
            if item.id and item.name and item.url then
                table.insert(result, item)
            end
        end
        
        return result
    end)

    if ok and sources and #sources > 0 then
        print("RSSStorage: Loaded " .. #sources .. " RSS sources from disk")
        return sources
    else
        print("RSSStorage: Failed to parse saved file, using defaults")
        return DEFAULT_RSS_SOURCES
    end
end

-- Save RSS sources to disk
function rss_storage.save(sources)
    if not sources or #sources == 0 then
        print("RSSStorage: No sources to save")
        return false
    end

    if not is_storage_available() then
        print("RSSStorage: Platform doesn't support file storage (memory only)")
        return true  -- Return true so operations succeed in memory
    end

    local platform = brls.Application.getPlatform()

    -- Build JSON string
    local parts = {"["}
    for i, source in ipairs(sources) do
        if i > 1 then
            table.insert(parts, ",")
        end
        table.insert(parts, '{"id":"')
        table.insert(parts, source.id or "")
        table.insert(parts, '","name":"')
        table.insert(parts, source.name or "")
        table.insert(parts, '","url":"')
        table.insert(parts, source.url or "")
        table.insert(parts, '"}')
    end
    table.insert(parts, "]")
    
    local json_str = table.concat(parts)
    
    local storage_path = get_storage_path()
    
    -- Ensure directory exists on desktop
    if storage_path:find("/") then
        local dir = storage_path:match("(.+)/[^/]+$")
        if dir then
            platform:mkdir(dir)
        end
    end
    
    print("RSSStorage: Saving to " .. storage_path)
    local success = platform:writeFile(storage_path, json_str)
    if success then
        print("RSSStorage: Saved " .. #sources .. " RSS sources to " .. storage_path)
        return true
    else
        print("RSSStorage: Failed to save to " .. storage_path)
        return false
    end
end

-- Add a new RSS source
function rss_storage.add_source(sources, name, url)
    if not name or name == "" or not url or url == "" then
        return nil, "Name and URL are required"
    end

    -- Check for duplicate URL
    for _, source in ipairs(sources) do
        if source.url == url then
            return nil, "This RSS source already exists"
        end
    end

    local new_source = {
        id = generate_id(name),
        name = name,
        url = url
    }

    table.insert(sources, new_source)
    
    -- Save to disk
    if rss_storage.save(sources) then
        return new_source, nil
    else
        -- Remove from memory if save failed
        table.remove(sources)
        return nil, "Failed to save to disk"
    end
end

-- Remove an RSS source by index
function rss_storage.remove_source(sources, index)
    if not index or index < 1 or index > #sources then
        return false, "Invalid index"
    end

    local removed = table.remove(sources, index)
    if removed then
        -- Save to disk
        if rss_storage.save(sources) then
            return true, nil
        else
            -- Restore if save failed
            table.insert(sources, index, removed)
            return false, "Failed to save to disk"
        end
    end
    
    return false, "Source not found"
end

-- Reset to defaults
function rss_storage.reset_to_defaults()
    rss_storage.save(DEFAULT_RSS_SOURCES)
    return DEFAULT_RSS_SOURCES
end

return rss_storage
