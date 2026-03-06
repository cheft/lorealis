-- network.lua - HTTP client wrapper using C++ bindings
-- Requires: brls.Network.get() and brls.Network.downloadImage() from C++ layer

-- Load JSON library
local ok, jsonlib = pcall(function() return require("utils/json") end)
if ok and jsonlib then
    print("Network: JSON library loaded successfully")
    -- Create global json object for compatibility with existing code
    json = jsonlib
else
    print("Network: Failed to load JSON library: " .. tostring(jsonlib))
end

local network = {}

-- Check if C++ network bindings are available
local has_cpp_network = pcall(function()
    return brls.Network and brls.Network.get
end)

-- HTTP GET request
-- @param url: URL to fetch
-- @param callback: function(success, response_body)
function network.get(url, callback)
    if not url or url == "" then
        print("Network: Empty URL")
        if callback then callback(false, nil) end
        return
    end
    
    if not has_cpp_network then
        print("Network: C++ network bindings not available")
        if callback then callback(false, nil) end
        return
    end
    
    print("Network: GET " .. url)
    
    return brls.Network.get(url, function(success, statusCode, response)
        if success then
            print("Network: Success, received " .. #response .. " bytes")
        else
            print("Network: Request failed with status " .. tostring(statusCode))
        end
        
        if callback then
            callback(success, response)
        end
    end)
end

-- Download image from URL
-- @param url: Image URL
-- @param callback: function(success, image_data_table)
--   image_data_table is a byte array that can be used with setImageFromMem
function network.download_image(url, callback)
    if not url or url == "" then
        print("Network: Empty image URL")
        if callback then callback(false, nil) end
        return
    end
    
    if not has_cpp_network then
        print("Network: C++ network bindings not available")
        if callback then callback(false, nil) end
        return
    end
    
    print("Network: Downloading image " .. url)
    
    return brls.Network.downloadImage(url, function(success, data)
        if success then
            print("Network: Image downloaded, " .. #data .. " bytes")
        else
            print("Network: Image download failed")
        end
        
        if callback then
            callback(success, data)
        end
    end)
end

-- Cancel request
function network.cancel(requestId)
    if not requestId then return end
    if has_cpp_network and brls.Network.cancel then
        brls.Network.cancel(requestId)
    end
end

-- JSON decode wrapper (if available)
function network.json_decode(str)
    if json and json.decode then
        local ok, result = pcall(function() return json.decode(str) end)
        if ok then
            return result
        else
            print("Network: JSON decode failed: " .. tostring(result))
            return nil
        end
    end
    return nil
end

return network
