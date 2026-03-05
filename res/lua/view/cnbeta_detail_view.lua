-- cnbeta_detail_view.lua - CnBeta News Detail View
local cnbeta_detail_view = {}
local image_cache = require("utils/image_cache")

-- Strip HTML tags for display
local function strip_html(html)
    if not html then return "无内容" end
    -- Remove script and style tags with content
    local text = html:gsub("<script[^>]*>[^<]*</script>", "")
    text = text:gsub("<style[^>]*>[^<]*</style>", "")
    
    -- Replace block-level tags with spaces/punctuation to prevent word merging
    text = text:gsub("<br%s*/?>", "\n")
    text = text:gsub("</p>", "\n\n")
    text = text:gsub("</div>", "\n")
    text = text:gsub("</li>", "\n")
    text = text:gsub("</td>", " ")
    text = text:gsub("</h1>", "\n")
    text = text:gsub("</h2>", "\n")
    text = text:gsub("</h3>", "\n")
    
    -- Remove all remaining HTML tags
    text = text:gsub("<[^>]+>", "")
    
    -- Decode entities
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    text = text:gsub("&amp;", "&")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&apos;", "'")
    text = text:gsub("&#39;", "'")
    text = text:gsub("&nbsp;", " ")
    
    -- Decode numeric entities (UTF-8 safe decoding)
    text = text:gsub("&#(%d+);", function(n) 
        local num = tonumber(n)
        if not num then return "" end
        if num < 128 then return string.char(num) end
        if num < 2048 then
            return string.char(192 + math.floor(num / 64), 128 + (num % 64))
        end
        return ""
    end)
    
    -- Collapse multiple spaces (but keep newlines)
    text = text:gsub("[ \t]+", " ")
    text = text:gsub("\n[ \t]+", "\n")
    text = text:gsub("[ \t]+\n", "\n")
    text = text:gsub("\n\n\n+", "\n\n")
    
    return text:match("^%s*(.-)%s*$") or "" -- trim
end

-- Format date for display
local function format_date(pub_date)
    if not pub_date or pub_date == "" then return "未知时间" end
    -- Convert RSS date format
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

function cnbeta_detail_view.init(view, news_data)
    print("CnBeta: Initializing detail view for " .. (news_data.title or "Unknown"))
    print("CnBeta: image_url = " .. tostring(news_data.image_url))
    print("CnBeta: has thumbnail view = " .. tostring(view:getView("thumbnail") ~= nil))
    
    -- Get all views
    local thumbnail = view:getView("thumbnail")
    local background_image = view:getView("background_image")
    local overlay = view:getView("overlay")
    local title = view:getView("title")
    local description = view:getView("description")
    local category = view:getView("category")
    local author = view:getView("author")
    local pub_date = view:getView("pub_date")
    local read_button = view:getView("read_button")
    local close_button = view:getView("close_button")
    
    -- Then load actual image if available (true = no debounce for immediate loading)
    if news_data.image_url and news_data.image_url ~= "" then
        print("CnBeta: Loading image from URL: " .. news_data.image_url)
        if thumbnail then
            print("CnBeta: Calling image_cache.load_image for thumbnail")
            image_cache.load_image(news_data.image_url, thumbnail, "img/game_bg.jpg", true)
        end
        -- if background_image then
        --     print("CnBeta: Calling image_cache.load_image for background")
        --     image_cache.load_image(news_data.image_url, background_image, "img/game_bg.jpg", true)
        -- end
    else
        print("CnBeta: No image_url available, using placeholder")
        if thumbnail then thumbnail:setImageFromRes("img/game_bg.jpg") end
        -- if background_image then background_image:setImageFromRes("img/game_bg.jpg") end
    end
    
    -- Theme-adaptive overlay color
    if overlay then
        local theme = brls.Application.getPlatform():getThemeVariant()
        if theme == brls.ThemeVariant.DARK then
            overlay:setBackgroundColor(brls.nvgRGBA(0, 0, 0, 192))
        else
            overlay:setBackgroundColor(brls.nvgRGBA(255, 255, 255, 192))
        end
    end
    
    -- Theme-adaptive colors
    local theme = brls.Application.getPlatform():getThemeVariant()
    local is_dark = (theme == brls.ThemeVariant.DARK)
    
    -- Color palette
    local color_category = is_dark and brls.nvgRGBA(46, 91, 255, 255) or brls.nvgRGBA(46, 91, 255, 255)  -- Blue
    local color_author = is_dark and brls.nvgRGBA(170, 170, 170, 255) or brls.nvgRGBA(100, 100, 100, 255)   -- Gray
    local color_date = is_dark and brls.nvgRGBA(255, 152, 0, 255) or brls.nvgRGBA(230, 81, 0, 255)      -- Orange
    local color_text = is_dark and brls.nvgRGBA(236, 240, 241, 255) or brls.nvgRGBA(44, 62, 80, 255)    -- Title/Desc color
    
    -- Set title
    if title then
        title:setText(news_data.title or "无标题")
        title:setTextColor(color_text)
    end
    
    -- Set description (detect HTML vs Plain Text)
    if description then
        local raw_content = news_data.full_content or news_data.summary or news_data.description or ""
        
        -- Comprehensive HTML detection: check for common tags or CDATA
        local html_tags = {
            "<p[%s>]", "<div[%s>]", "<br[/%s>]", "<h[1-6][%s>]",
            "<a[%s>]", "<img[%s>]", "<ul[%s>]", "<ol[%s>]",
            "<li[%s>]", "<blockquote[%s>]", "<span[%s>]",
            "<!%[CDATA%[", "<strong>", "<b>", "<em>", "<i>"
        }
        
        local is_html = false
        local lower_content = raw_content:lower()
        for _, tag in ipairs(html_tags) do
            if lower_content:match(tag) then
                is_html = true
                break
            end
        end
        
        -- Find index of description in detail_box to insert at same position
        local detail_box = view:getView("detail_box")

        if is_html then
            print("CnBeta: HTML detected for [" .. (news_data.title or "Unknown") .. "], using HtmlRenderer")
            -- Hide the original label
            description:setVisibility(brls.Visibility.GONE)
            
            -- Create and insert HtmlRenderer
            local renderer = brls.HtmlRenderer.new()
            renderer:renderString(raw_content)
            
            if detail_box then
                -- Note: Borealis doesn't have child index query in Lua directly, 
                -- but we know description is the 2nd main element (index 1 in 0-based C++) after the header row (index 0)
                -- Tag index 0: Header Box
                -- Tag index 1: Description Label (to be replaced)
                -- Tag index 2: Action Bar
                detail_box:addView(renderer, 1)
            end
        else
            print("CnBeta: Plain text detected, using standard Label")
            local content = strip_html(raw_content)
            if content == "" then
                content = "暂无内容摘要"
            end
            description:setText(content)
            description:setTextColor(color_text)
        end
    end
    
    -- Set category
    if category then
        category:setText(news_data.category or "科技")
        category:setTextColor(color_category)
    end
    
    -- Set author
    if author then
        author:setText(news_data.author or "CnBeta")
        author:setTextColor(color_author)
    end
    
    -- Set publish date
    if pub_date then
        pub_date:setText(format_date(news_data.pub_date))
        pub_date:setTextColor(color_date)
    end
    
    -- Read button - open article URL
    if read_button then
        read_button:onClick(function(v)
            print("CnBeta: Read button clicked for " .. (news_data.title or "Unknown"))
            
            if news_data.link and news_data.link ~= "" then
                print("CnBeta: Opening URL " .. news_data.link)
                -- Use Switch built-in browser
                local platform = brls.Application.getPlatform()
                if platform and platform.openBrowser then
                    platform:openBrowser(news_data.link)
                else
                    print("CnBeta: Browser not available on this platform")
                end
            end
            
            return true
        end)
    end
    
    -- Close button - dismiss the view
    if close_button then
        close_button:onClick(function(v)
            print("CnBeta: Closing detail view")
            view:dismiss()
            return true
        end)
    end
    
    
    -- Restore state when leaving
    view:onWillDisappear(function()
        -- Cancel image loads
        if thumbnail then image_cache.cancel_load(thumbnail) end
        -- if background_image then image_cache.cancel_load(background_image) end
    end)
end

return cnbeta_detail_view