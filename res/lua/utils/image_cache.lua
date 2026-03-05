-- image_cache.lua - Image loading and caching utility using C++ network bindings
local image_cache = {}
local network = require("utils/network")

-- Cache storage: url -> {data = byte_table, timestamp = number}
local cache = {}

-- Track active requests: url -> {view_refs = {{view_key, id}, ...}, request_id = number}
local active_requests = {}

-- Track what each view is currently supposed to show (URL and unique ID)
-- Key: view_key (stable address), Value: { url: string, id: number }
local view_targets = {}

-- Next unique load ID to prevent stale callback races
local next_load_id = 1000

-- Maximum cache size (number of images)
local MAX_CACHE_SIZE = 150

-- Debounce delay in milliseconds
local DEBOUNCE_DELAY = 500

-- Track debounce timers
-- Key: view_key (stable address), Value: timer_id
local debounce_timers = {}

-- Stable key retrieval for views
local function get_view_key(view)
    if not view then return nil end
    if view.get_address then
        return tostring(view:get_address())
    end
    -- Fallback to tostring which usually includes address in userdata
    return tostring(view)
end

-- Generate a cache key from URL
local function get_cache_key(url)
    if not url then return "" end
    local hash = 0
    for i = 1, #url do
        hash = ((hash * 31) + string.byte(url, i)) % 1000000007
    end
    return tostring(hash)
end

-- Clean old cache entries
local function cleanup_cache()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    
    if count > MAX_CACHE_SIZE then
        local oldest_key = nil
        local oldest_time = os.time() + 1000
        for key, entry in pairs(cache) do
            if entry.timestamp < oldest_time then
                oldest_time = entry.timestamp
                oldest_key = key
            end
        end
        if oldest_key then cache[oldest_key] = nil end
    end
end

-- Cancel any active load for a view
function image_cache.cancel_load(view)
    if not view then return end
    local vkey = get_view_key(view)
    
    -- 1. Cancel debounce timer
    if debounce_timers[vkey] then
        brls.cancelDelay(debounce_timers[vkey])
        debounce_timers[vkey] = nil
        -- print(string.format("ImageCache: [TIMER] Cancelled %s", vkey))
    end
    
    -- 2. Check active target
    local state = view_targets[vkey]
    if not state then return end
    
    local url = state.url
    local load_id = state.id
    view_targets[vkey] = nil -- Mark as not waiting
    
    local cache_key = get_cache_key(url)
    local request = active_requests[cache_key]
    if request then
        -- Remove this view's specific reference from the shared request
        local found = false
        for i, ref in ipairs(request.view_refs) do
            if ref.vkey == vkey and ref.id == load_id then
                table.remove(request.view_refs, i)
                found = true
                break
            end
        end
        
        -- If no more views are waiting, ABORT the network request
        if #request.view_refs == 0 then
            if request.request_id then
                print(string.format("ImageCache: [ABORT] Killing network request %d for %s", request.request_id, url))
                network.cancel(request.request_id)
            end
            active_requests[cache_key] = nil
        end
    end
end

-- Load image with precise tracking
function image_cache.load_image(url, image_view, default_res, no_debounce)
    print(string.format("ImageCache: load_image called url=%s, no_debounce=%s", tostring(url), tostring(no_debounce)))
    
    if not url or url == "" then
        print("ImageCache: Empty URL, setting default")
        if default_res and image_view then
            pcall(function() image_view:setImageFromRes(default_res) end)
        end
        return
    end
    
    if not image_view then 
        print("ImageCache: No image_view provided")
        return 
    end
    local vkey = get_view_key(image_view)
    print(string.format("ImageCache: view_key=%s", tostring(vkey)))
    
    -- 1. Cancel any previous attempt for this view (but only if different URL)
    local prev_target = view_targets[vkey]
    if prev_target and prev_target.url ~= url then
        print(string.format("ImageCache: Cancelling previous load for different URL: %s -> %s", prev_target.url, url))
        image_cache.cancel_load(image_view)
    end
    
    -- 2. Check Memory Cache
    local cache_key = get_cache_key(url)
    if cache[cache_key] then
        cache[cache_key].timestamp = os.time()
        local data = cache[cache_key].data
        pcall(function()
            if image_view.setImageFromMem then
                image_view:setImageFromMem(data)
                if image_view.invalidate then image_view:invalidate() end
                local p = image_view:getParent()
                if p and p.invalidate then p:invalidate() end
            end
        end)
        return
    end

    -- 3. Mark target and unique ID
    next_load_id = next_load_id + 1
    local current_load_id = next_load_id
    view_targets[vkey] = { url = url, id = current_load_id }
    
    -- 4. Set Placeholder
    if default_res then
        pcall(function() 
            image_view:setImageFromRes(default_res) 
            if image_view.invalidate then image_view:invalidate() end
        end)
    end
    
    -- 5. Define start logic
    local function do_start()
        -- Guard: Is this view still waiting for THIS EXACT URL and ID?
        local state = view_targets[vkey]
        if not state or state.id ~= current_load_id then
            return
        end
        
        -- 6. Check for shared request
        local existing = active_requests[cache_key]
        if existing then
            table.insert(existing.view_refs, {vkey = vkey, view = image_view, id = current_load_id})
            -- print(string.format("ImageCache: [JOIN] View %s joining for %s", vkey, url))
            return
        end
        
        -- 7. Start new network request
        local request_tracker = {
            view_refs = {{vkey = vkey, view = image_view, id = current_load_id}},
            request_id = nil
        }
        active_requests[cache_key] = request_tracker
        
        print(string.format("ImageCache: [START] Downloading %s", url))
        local rid = network.download_image(url, function(success, data)
            print(string.format("ImageCache: [CALLBACK] success=%s, data_len=%s", tostring(success), tostring(data and #data or 0)))
            -- ONLY clear if this is still the active tracker
            if active_requests[cache_key] == request_tracker then
                active_requests[cache_key] = nil
            end
            
            if not success or not data then 
                print(string.format("ImageCache: [FAILED] Download failed for %s", url))
                return 
            end
            
            -- Store in cache
            cleanup_cache()
            cache[cache_key] = { data = data, timestamp = os.time() }
            
            -- Apply to all views that are STILL waiting for THIS EXACT REQUEST
            local apply_count = 0
            for _, ref in ipairs(request_tracker.view_refs) do
                local v = ref.view
                local target_id = ref.id
                local tvkey = ref.vkey
                pcall(function()
                    local s = view_targets[tvkey]
                    if s and s.id == target_id then
                        v:setImageFromMem(data)
                        if v.invalidate then v:invalidate() end
                        local p = v:getParent()
                        if p and p.invalidate then p:invalidate() end
                        view_targets[tvkey] = nil
                        apply_count = apply_count + 1
                    end
                end)
            end
            if apply_count > 0 then
                print(string.format("ImageCache: [FINISH] Applied %s to %d views", url, apply_count))
            end
        end)
        
        request_tracker.request_id = rid
        -- print(string.format("ImageCache: [START] Request ID %s for %s", tostring(rid), url))
    end

    -- 8. Execution
    if no_debounce then
        do_start()
    else
        debounce_timers[vkey] = brls.delay(DEBOUNCE_DELAY, function()
            debounce_timers[vkey] = nil
            do_start()
        end)
    end
end

-- Clear state
function image_cache.clear()
    cache = {}
    for _, request in pairs(active_requests) do
        if request.request_id then network.cancel(request.request_id) end
    end
    active_requests = {}
    view_targets = {}
    for vkey, timer in pairs(debounce_timers) do
        brls.cancelDelay(timer)
    end
    debounce_timers = {}
end

return image_cache
