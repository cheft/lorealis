-- rss_list_tab.lua - Multi-RSS News List Tab
local rss_detail_view = require("view/rss_detail_view")
local network = require("utils/network")
local image_cache = require("utils/image_cache")
local rss_storage = require("utils/rss_storage")
local rss_list_tab = {}

-- State tracking
local all_news = {}
local is_loading = false
local initial_instant_count = 0

-- RSS Sources - Loaded from disk (with defaults)
local RSS_SOURCES = rss_storage.load()

local current_source_index = 1
local current_request_id = nil

-- XML parsing helper - extract text between tags
local function extract_tag(xml, tag)
    if not xml or not tag then return nil end
    -- Handle both <tag>content</tag> and <tag attr="...">content</tag>
    local pattern = "<" .. tag .. "[^>]*>(.-)</" .. tag .. ">"
    local content = xml:match(pattern)
    if content then
        -- Decode common HTML entities (use raw entities)
        content = content:gsub("&lt;", "<")
        content = content:gsub("&gt;", ">")
        content = content:gsub("&amp;", "&")
        content = content:gsub("&quot;", '\"')
        content = content:gsub("&apos;", "'")
        content = content:gsub("<!%[CDATA%[", "")
        content = content:gsub("%]%]>", "")
        -- Remove remaining CDATA markers if any
        content = content:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
        return content:match("^%s*(.-)%s*$") -- trim whitespace
    end
    return nil
end

-- Extract image URL from HTML content (for CnBeta)
local function extract_image_url_from_html(html)
    if not html then return nil end
    -- Look for img src
    local img_url = html:match('<img[^>]+src=["\']([^"\']+)["\']')
    if img_url then
        -- Handle relative URLs
        if img_url:sub(1, 4) ~= "http" then
            if img_url:sub(1, 2) == "//" then
                img_url = "https:" .. img_url
            elseif img_url:sub(1, 1) == "/" then
                img_url = "https://www.cnbeta.com.tw" .. img_url
            end
        end
        return img_url
    end
    return nil
end

-- Extract image URL from enclosure tag (for Gcores RSS)
local function extract_image_url_from_enclosure(item_xml)
    if not item_xml then return nil end
    -- Look for <enclosure url="..." type="image/..." />
    local url, type_attr = item_xml:match('<enclosure[^>]+url=["\']([^"\']+)["\'][^>]*type=["\']([^"\']+)["\']')
    if url and type_attr and type_attr:find("image") then
        return url
    end
    -- Try reverse order (type before url)
    url = item_xml:match('<enclosure[^>]+type=["\']image/[^"\']*["\'][^>]+url=["\']([^"\']+)["\']')
    if url then
        return url
    end
    -- Just try to get url attribute
    url = item_xml:match('<enclosure[^>]+url=["\']([^"\']+)["\']')
    if url then
        return url
    end
    return nil
end

-- Extract image URL from media:thumbnail or media:content (common in RSS 2.0 with media namespace)
local function extract_image_url_from_media(item_xml)
    if not item_xml then return nil end
    -- Try media:thumbnail
    local url = item_xml:match('<media:thumbnail[^>]+url=["\']([^"\']+)["\']')
    if url then
        return url
    end
    -- Try media:content with image type
    local media_content = item_xml:match('<media:content[^>]+type=["\']image/[^"\']*["\'][^>]*>(.-)</media:content>')
    if media_content then
        url = media_content:match('url=["\']([^"\']+)["\']')
        if url then
            return url
        end
    end
    return nil
end

-- Strip HTML tags for plain text summary
local function strip_html(html)
    if not html then return "" end
    -- Remove script and style tags with content
    local text = html:gsub("<script[^>]*>[^<]*</script>", "")
    text = text:gsub("<style[^>]*>[^<]*</style>", "")
    
    -- Replace block-level tags with spaces/punctuation to prevent word merging
    text = text:gsub("<br%s*/?>", " ")
    text = text:gsub("</p>", " ")
    text = text:gsub("</div>", " ")
    text = text:gsub("</li>", " ")
    text = text:gsub("</td>", " ")
    text = text:gsub("</h1>", ". ")
    text = text:gsub("</h2>", ". ")
    text = text:gsub("</h3>", ". ")
    
    -- Remove all remaining HTML tags
    text = text:gsub("<[^>]+>", " ")
    
    -- Decode entities
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    text = text:gsub("&amp;", "&")
    text = text:gsub("&quot;", '\"')
    text = text:gsub("&apos;", "'")
    text = text:gsub("&#39;", "'")
    text = text:gsub("&nbsp;", " ")
    
    -- Decode numeric entities (UTF-8 safe decoding)
    text = text:gsub("&#(%d+);", function(n) 
        local num = tonumber(n)
        if not num then return "" end
        -- Basic ASCII
        if num < 128 then return string.char(num) end
        -- Simple UTF-8 encoding for common characters
        if num < 2048 then
            return string.char(192 + math.floor(num / 64), 128 + (num % 64))
        end
        return "" -- Skip higher order for now or use a proper UTF-8 library if available
    end)
    
    -- Collapse multiple spaces/newlines
    text = text:gsub("%s+", " ")
    return text:match("^%s*(.-)%s*$") or "" -- trim
end

-- UTF-8 safe truncation
local function utf8_truncate(str, max_len)
    if not str or #str <= max_len then return str end
    
    -- Find the last valid UTF-8 start byte before max_len
    local len = max_len
    while len > 0 do
        local byte = string.byte(str, len)
        -- UTF-8 start byte: 0xxxxxxx or 11xxxxxx
        if byte < 128 or byte >= 192 then
            break
        end
        len = len - 1
    end
    
    return str:sub(1, len - 1) .. "..."
end

-- Extract RSS/Atom feed links from HTML head
local function discover_feed_links(html)
    if not html then return nil end
    local feeds = {}
    -- Look for <link rel="alternate" type="application/rss+xml" href="...">
    -- also handle application/atom+xml
    for link in html:gmatch('<link[^>]+rel=["\']alternate["\'][^>]*>') do
        local type_attr = link:match('type=["\']([^"\']+)["\']')
        local href = link:match('href=["\']([^"\']+)["\']')
        if href and type_attr then
            if type_attr:find("rss%+xml") or type_attr:find("atom%+xml") then
                table.insert(feeds, href)
            end
        end
    end
    return #feeds > 0 and feeds or nil
end

-- Parse RSS XML and extract news items
local function parse_rss(xml_content, url)
    if not xml_content or xml_content == "" then
        return nil, "Empty XML content"
    end
    
    -- Check if this is actually HTML
    if xml_content:find("^%s*<![Dd][Oo][Cc][Tt][Yy][Pp][Ee]%s+[Hh][Tt][Mm][Ll]") or 
       xml_content:find("^%s*<[Hh][Tt][Mm][Ll]") or
       xml_content:find("<[Bb][Oo][Dd][Yy]") then
        print("NewsTab: Detected HTML instead of XML")
        local feeds = discover_feed_links(xml_content)
        if feeds then
            print("NewsTab: Found " .. #feeds .. " feed links in HTML")
            return {is_html = true, feeds = feeds}
        end
        return nil, "Received HTML content instead of RSS (possibly Cloudflare/Protection)"
    end
    
    local news_items = {}
    local is_atom = xml_content:find("<feed[^>]*xmlns=\"http://www%.w3%.org/2005/Atom\"") ~= nil
    
    print("NewsTab: Parsing XML, is_atom=" .. tostring(is_atom))
    
    -- Debug: show first 200 chars of XML
    print("NewsTab: XML preview: " .. xml_content:sub(1, 200):gsub("\n", " "))
    
    -- Try RSS format first (<item> tags)
    -- Find all <item> elements (handle attributes and different formats)
    local item_count = 0
    for item_xml in xml_content:gmatch("<item[^>]*>(.-)</item>") do
        item_count = item_count + 1
        if item_count <= 3 then  -- Debug first 3 items
            print("NewsTab: Found item #" .. item_count .. ", length=" .. #item_xml)
        end
        local item = {}
        
        -- Extract basic fields
        item.title = extract_tag(item_xml, "title") or "无标题"
        item.link = extract_tag(item_xml, "link") or ""
        -- Try content:encoded first (Steam uses this), then description
        item.description = extract_tag(item_xml, "content:encoded") or extract_tag(item_xml, "description") or ""
        item.pub_date = extract_tag(item_xml, "pubDate") or ""
        item.guid = extract_tag(item_xml, "guid") or ""
        item.author = extract_tag(item_xml, "author") or extract_tag(item_xml, "dc:creator") or ""
        item.category = extract_tag(item_xml, "category") or ""
        
        -- Extract image - try all methods in order of reliability
        -- 1. Try enclosure first (most reliable)
        item.image_url = extract_image_url_from_enclosure(item_xml)
        -- 2. Try media tags
        if not item.image_url then
            item.image_url = extract_image_url_from_media(item_xml)
        end
        -- 3. Try to extract from description HTML
        if not item.image_url then
            item.image_url = extract_image_url_from_html(item.description)
        end
        
        -- Create full content for detail view (untruncated)
        item.full_content = item.description
        
        -- Create plain text summary (truncated)
        item.summary = utf8_truncate(strip_html(item.description), 400)
        
        -- Clean up title (remove CDATA markers if any)
        item.title = item.title:gsub("<!%[CDATA%[", ""):gsub("%]%]>", "")
        
        -- Set default author/category if empty
        if item.author == "" then
            item.author = "未知来源"
        end
        if item.category == "" then
            item.category = "资讯"
        end
        
        table.insert(news_items, item)
    end
    
    print("NewsTab: Found " .. item_count .. " RSS items, parsed " .. #news_items)
    
    -- If no RSS items found, try Atom format (<entry> tags)
    if #news_items == 0 then
        print("NewsTab: No RSS items found, trying Atom format")
        local entry_count = 0
        for entry_xml in xml_content:gmatch("<entry[^>]*>(.-)</entry>") do
            entry_count = entry_count + 1
            local item = {}
            
            -- Atom uses different tag names
            item.title = extract_tag(entry_xml, "title") or "无标题"
            -- Atom links are in <link href="..."/>
            item.link = entry_xml:match('<link[^>]+href=["\']([^"\']+)["\']') or ""
            -- Atom content can be in <content> or <summary>
            item.description = extract_tag(entry_xml, "content") or extract_tag(entry_xml, "summary") or ""
            item.pub_date = extract_tag(entry_xml, "updated") or extract_tag(entry_xml, "published") or ""
            item.guid = extract_tag(entry_xml, "id") or ""
            item.author = extract_tag(entry_xml, "author") or ""
            item.category = extract_tag(entry_xml, "category") or ""
            
            -- Extract image from content/description
            item.image_url = extract_image_url_from_html(item.description)
            
            -- Create full content for detail view
            item.full_content = item.description
            
            -- Create plain text summary
            item.summary = utf8_truncate(strip_html(item.description), 400)
            
            -- Clean up title
            item.title = item.title:gsub("<!%[CDATA%[", ""):gsub("%]%]>", "")
            
            -- Set defaults
            if item.author == "" then
                item.author = "未知来源"
            end
            if item.category == "" then
                item.category = "资讯"
            end
            
            table.insert(news_items, item)
        end
        print("NewsTab: Found " .. entry_count .. " Atom entries, parsed " .. #news_items)
    end
    
    print("NewsTab: Parsed " .. #news_items .. " items total")
    return news_items
end

-- Format date for display
local function format_date(pub_date)
    if not pub_date or pub_date == "" then return "" end
    -- Convert RSS date format to simpler format
    -- Input: "Wed, 03 Mar 2026 10:30:00 GMT"
    -- Output: "2026-03-03 10:30"
    local day, month_str, year, time = pub_date:match("%w+, (%d+) (%w+) (%d+) (%d+:%d+):%d+")
    if day and month_str and year and time then
        local months = {
            Jan = "01", Feb = "02", Mar = "03", Apr = "04",
            May = "05", Jun = "06", Jul = "07", Aug = "08",
            Sep = "09", Oct = "10", Nov = "11", Dec = "12"
        }
        local month = months[month_str] or "01"
        return year .. "-" .. month .. "-" .. day .. " " .. time
    end
    return pub_date
end

-- Fetch news from RSS feed
local function fetch_news(source_index, callback)
    is_loading = true
    local source = RSS_SOURCES[source_index]
    if not source then
        print("NewsTab: Invalid source index " .. tostring(source_index))
        is_loading = false
        if callback then callback(false) end
        return nil
    end
    
    print("NewsTab: Fetching RSS from " .. source.name .. "...")
    
    return network.get(source.url, function(success, response)
        is_loading = false
        if success and response then
            print("NewsTab: Received " .. #response .. " bytes from " .. source.name)
            
            -- Parse RSS XML
            local news_items, err = parse_rss(response, source.url)
            
            if news_items and not news_items.is_html and #news_items > 0 then
                all_news = news_items
                print("NewsTab: Loaded " .. #all_news .. " news items from " .. source.name)
                if callback then callback(true) end
            elseif news_items and news_items.is_html then
                print("NewsTab: Received HTML for existing source " .. source.name .. ", feed discovery possible")
                brls.Application.notify("Source " .. source.name .. " returned HTML. Try updating URL.")
                all_news = {}
                if callback then callback(false) end
            else
                print("NewsTab: Error parsing RSS: " .. tostring(err))
                brls.Application.notify("Error parsing: " .. tostring(err))
                all_news = {}
                if callback then callback(false) end
            end
        else
            print("NewsTab: Network error for " .. source.name)
            all_news = {}
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

-- Switch to a different RSS source
local function switch_source(new_index, recycler, source_selector)
    if new_index == current_source_index then return end
    if new_index < 1 or new_index > #RSS_SOURCES then return end
    
    print("NewsTab: Switching from " .. RSS_SOURCES[current_source_index].name .. " to " .. RSS_SOURCES[new_index].name)
    
    -- Cancel any ongoing request
    if current_request_id then
        network.cancel(current_request_id)
        current_request_id = nil
    end
    
    -- Update current index
    current_source_index = new_index
    
    -- Update UI (button text is updated in the dropdown callback)
    
    -- Clear current data and reload
    all_news = {}
    update_recycler(recycler)
    
    -- Fetch new data
    current_request_id = fetch_news(current_source_index, function(success)
        update_recycler(recycler)
        current_request_id = nil
    end)
end

-- Initialize the tab view
function rss_list_tab.init(view)
    if not view then return end
    
    local recycler = view:getView("recycler")
    local source_selector = view:getView("source_selector")
    
    -- Setup source selector (using a single Button with Dropdown)
    if source_selector then
        source_selector:setText(RSS_SOURCES[current_source_index].name)
        
        source_selector:onClick(function()
            -- Create dropdown with source options
            local items = {}
            for _, source in ipairs(RSS_SOURCES) do
                table.insert(items, source.name)
            end
            
            local dropdown = brls.Dropdown.new(
                "Select Source",
                items,
                function(selected)
                    if selected >= 0 then
                        local new_index = selected + 1 -- Dropdown is 0-indexed
                        print("NewsTab: Source selected: " .. tostring(new_index))
                        switch_source(new_index, recycler, source_selector)
                        source_selector:setText(RSS_SOURCES[new_index].name)
                    end
                end,
                current_source_index - 1
            )
            brls.Application.pushActivity(dropdown)
            return true
        end)
    end
    
    -- Helper function to extract domain from URL
    local function extract_domain_id(url)
        if not url or url == "" then return nil end
        -- Extract domain from URL: https://www.example-site.com/path -> example-site
        local domain = url:match("https?://([^/]+)")
        if not domain then return nil end
        -- Remove www. prefix if present
        domain = domain:gsub("^www%.", "")
        -- Extract main domain name (before first dot)
        local main_name = domain:match("^([^.]+)")
        return main_name or domain
    end
    
    -- Helper function to fetch and parse RSS title
    local function fetch_rss_title(url, callback)
        network.get(url, function(success, response)
            if not success or not response or response == "" then
                callback(nil, "Failed to fetch RSS")
                return
            end
            
            -- Try to extract title from RSS
            local res, err = parse_rss(response, url)
            
            if res and res.is_html then
                -- Discovery! Try the first feed found
                local discovered_url = res.feeds[1]
                if discovered_url:sub(1, 4) ~= "http" then
                    -- Handle relative path
                    if discovered_url:sub(1, 1) == "/" then
                        local domain = url:match("(https?://[^/]+)")
                        discovered_url = domain .. discovered_url
                    else
                        local base = url:match("(https?://.+/)")
                        discovered_url = base .. discovered_url
                    end
                end
                print("NewsTab: Discovering feed from " .. discovered_url)
                brls.Application.notify("Discovered: " .. discovered_url)
                fetch_rss_title(discovered_url, callback)
                return
            end
            
            local title = nil
            if res and #res > 0 then
                -- Search response for channel title if it's RSS
                local channel = response:match("<channel[^>]*>(.-)</channel>")
                if channel then
                    title = channel:match("<title[^>]*>(.-)</title>")
                end
                
                -- Try Atom format: <feed><title>...</title></feed>
                if not title then
                    local feed = response:match("<feed[^>]*>(.-)</feed>")
                    if feed then
                        title = feed:match("<title[^>]*>(.-)</title>")
                    end
                end
                
                -- Fallback to first item's title or something
                if not title then
                    title = response:match("<title[^>]*>(.-)</title>")
                end
            end
            
            -- Clean up title (remove CDATA if present)
            if title then
                title = title:gsub("<!%[CDATA%[", ""):gsub("%]%]>", "")
                title = title:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
                title = title:match("^%s*(.-)%s*$") -- trim
            end
            
            if title and title ~= "" then
                -- Return discovered URL if we followed a redirect/discovery
                callback(title, nil, url)
            else
                callback(nil, err or "No title found in RSS", url)
            end
        end)
    end
    
    -- Setup Add RSS InputCell (hidden, triggered by + button)
    local add_rss_button = view:getView("add_rss_button")
    local rss_url_input = view:getView("rss_url_input")
    
    if add_rss_button and rss_url_input then
        -- Initialize the input cell (hidden but functional)
        rss_url_input:init("Add RSS Source", "", function(text)
            if not text or text == "" then
                return
            end
            
            -- Validate URL format
            if not text:match("^https?://") then
                brls.Application.notify("Invalid URL: Must start with http:// or https://")
                return
            end
            
            -- Extract domain as ID
            local id = extract_domain_id(text)
            if not id then
                brls.Application.notify("Invalid URL format")
                return
            end
            
            -- Check if already exists
            for _, existing in ipairs(RSS_SOURCES) do
                if existing.url == text then
                    brls.Application.notify("This RSS source already exists")
                    return
                end
            end
            
            brls.Application.notify("Fetching RSS info...")
            
            -- Fetch RSS title
            fetch_rss_title(text, function(title, err, effective_url)
                local final_url = effective_url or text
                if not title then
                    -- Use ID as fallback name
                    title = id:gsub("-", " "):gsub("_", " ")
                    title = title:gsub("(%a)(%S*)", function(first, rest)
                        return first:upper() .. rest:lower()
                    end)
                end
                
                -- Add to sources
                local success = rss_storage.add_source(RSS_SOURCES, title, final_url)
                if success then
                    print("NewsTab: Added new RSS source: " .. title .. " (" .. id .. ")")
                    brls.Application.notify("Added: " .. title)
                    -- Clear the input value for next time
                    rss_url_input:setValue("")
                else
                    -- Add to memory even if save failed
                    table.insert(RSS_SOURCES, {id = id, name = title, url = final_url})
                    print("NewsTab: Added to memory only: " .. title)
                    brls.Application.notify("Added (memory only): " .. title)
                end
                
                -- Clear the detail (value) after adding, keep title
                if rss_url_input.detail then
                    rss_url_input.detail:setText("")
                end
            end)
        end, "Add RSS", "https://example.com/feed.xml", 256)
        
        -- Click + button to show keyboard directly
        add_rss_button:onClick(function()
            -- Trigger input dialog directly
            rss_url_input:openKeyboard(256)
            return true
        end)
    end
    
    -- Setup Delete RSS button
    local delete_rss_button = view:getView("delete_rss_button")
    if delete_rss_button then
        delete_rss_button:onClick(function()
            if #RSS_SOURCES <= 1 then
                brls.Application.notify("Cannot delete: At least one source required")
                return true
            end
            
            -- Show dropdown to select which source to delete
            local items = {}
            for _, source in ipairs(RSS_SOURCES) do
                table.insert(items, source.name)
            end
            
            local dropdown = brls.Dropdown.new(
                "Delete RSS Source",
                items,
                function(selected)
                    if selected >= 0 then
                        local index = selected + 1
                        local source_name = RSS_SOURCES[index].name
                        
                        local success, err = rss_storage.remove_source(RSS_SOURCES, index)
                        if success then
                            print("NewsTab: Deleted RSS source: " .. source_name)
                            -- Adjust current index if needed
                            if current_source_index > #RSS_SOURCES then
                                current_source_index = #RSS_SOURCES
                            end
                            if current_source_index == index then
                                current_source_index = 1
                            end
                            -- Refresh UI
                            source_selector:setText(RSS_SOURCES[current_source_index].name)
                            switch_source(current_source_index, recycler, source_selector)
                            brls.Application.notify("Deleted: " .. source_name)
                        else
                            print("NewsTab: Failed to delete: " .. tostring(err))
                            brls.Application.notify("Error: " .. tostring(err))
                        end
                    end
                end,
                -1  -- No pre-selection
            )
            brls.Application.pushActivity(dropdown)
            return true
        end)
    end
    
    if recycler then
        -- Register MessageCell for loading/empty states
        recycler:registerCell("MessageCell", function()
            return brls.RecyclerCell.createFromXML("xml/cells/message_cell.xml")
        end)
        
        -- Register RSSCell for news items
        recycler:registerCell("RSSCell", function()
            local cell = brls.RecyclerCell.createFromXML("xml/cells/rss_cell.xml")
            if cell.setPrepareForReuseCallback then
                cell:setPrepareForReuseCallback(function()
                    -- Check if cell is still valid before accessing
                    if not cell or type(cell) ~= "userdata" then return end
                    local thumbnail = cell:getView("thumbnail")
                    if thumbnail then
                        print(string.format("NewsTab: [REUSE] View %s", tostring(thumbnail)))
                        image_cache.cancel_load(thumbnail)
                    end
                end)
            end
            
            -- Cancel when cell is hidden
            if cell.onWillDisappear then
                cell:onWillDisappear(function()
                    -- Check if cell is still valid before accessing
                    if not cell or type(cell) ~= "userdata" then return end
                    local thumbnail = cell:getView("thumbnail")
                    if thumbnail then
                        print(string.format("NewsTab: [HIDE] View %s", tostring(thumbnail)))
                        image_cache.cancel_load(thumbnail)
                    end
                end)
            end
            return cell
        end)
        
        -- Data source
        local dataSource = {
            numberOfSections = function() return 1 end,
            numberOfRows = function() 
                if is_loading then return 1 end
                if #all_news == 0 then return 1 end
                return #all_news 
            end,
            cellForRow = function(rc, section, row)
                -- Loading state
                if is_loading then
                    local cell = rc:dequeueReusableCell("MessageCell")
                    local label = cell:getView("message_label")
                    if label then label:setText("加载中...") end
                    return cell
                end
                
                -- Empty state
                if #all_news == 0 then
                    local cell = rc:dequeueReusableCell("MessageCell")
                    local label = cell:getView("message_label")
                    if label then label:setText("暂无新闻") end
                    return cell
                end
                
                -- News item
                local cell = rc:dequeueReusableCell("RSSCell")
                if not cell then return nil end
                
                local news = all_news[row + 1]
                if news then
                    local title = cell:getView("title")
                    local desc = cell:getView("description")
                    local category = cell:getView("category")
                    local author = cell:getView("author")
                    local pub_date = cell:getView("pub_date")
                    local thumbnail = cell:getView("thumbnail")
                    
                    if title then title:setText(news.title) end
                    if desc then 
                        local summary = news.summary or ""
                        if #summary > 80 then 
                            summary = summary:sub(1, 77) .. "..." 
                        end
                        desc:setText(summary) 
                    end
                    if category then category:setText(news.category) end
                    if author then author:setText(news.author) end
                    if pub_date then pub_date:setText(format_date(news.pub_date)) end
                    
                    -- Load thumbnail with image cache (like game_list_tab)
                    if thumbnail then
                        local current_source = RSS_SOURCES[current_source_index]
                        if news.image_url and news.image_url ~= "" then
                            -- Use image cache for loading with debounce
                            local should_instant = (row < 10)
                            image_cache.load_image(news.image_url, thumbnail, "img/game_bg.jpg", should_instant)
                        else
                            -- No image available, use placeholder
                            thumbnail:setImageFromRes("img/game_bg.jpg")
                        end
                    end
                end
                return cell
            end,
            heightForRow = function(rc, section, row) return 110 end,
            didSelectRowAt = function(rc, section, row)
                if is_loading or #all_news == 0 then return end
                local news = all_news[row + 1]
                if news then
                    local detail = brls.Application.loadXMLRes("xml/views/rss_detail.xml")
                    if detail then
                        rss_detail_view.init(detail, news)
                        rc:present(detail)
                    end
                end
            end
        }
        
        recycler:setDataSource(dataSource)
        
        -- Initial load
        current_request_id = fetch_news(current_source_index, function(success)
            update_recycler(recycler)
            current_request_id = nil
        end)
        
        -- Cleanup on tab switch
        view:onWillDisappear(function()
            if current_request_id then
                print("NewsTab: Tab disappearing, cancelling RSS request")
                network.cancel(current_request_id)
                current_request_id = nil
            end
            -- Also cancel any ongoing image loads (handled by recycler cells)
        end)
    end
end

return rss_list_tab
