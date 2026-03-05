-- zip_view_loader.lua
-- Helper for dynamically loading views from ZIP packages.
--
-- Usage:
--   local loader = require("utils/zip_view_loader")
--
--   local view, mod = loader.load("hello_view.blpkg", "hello.xml", "hello_view.lua")
--   if view and mod then mod.init(view) end

local zip_view_loader = {}

-- ============================================================
-- Platform-aware base path for pkg files
-- NS:      sdmc:/switch/ns_dashboard/pkgs/
-- Others:  pkgs/  (relative to working dir)
-- ============================================================
local function getPkgsBaseDir()
    local ok, platform = pcall(function()
        return brls.Application.getPlatform():getName()
    end)
    if ok and platform == "Switch" then
        return "sdmc:/switch/ns_dashboard/pkgs/"
    end
    return "pkgs/"
end

--- Resolve a package filename to its full absolute/relative path.
-- If path is already absolute (starts with / or X:), it is returned as-is.
local function resolvePkgPath(filename)
    if filename:sub(1,1) == "/" or filename:match("^%a+:/") then
        return filename  -- already absolute
    end
    return getPkgsBaseDir() .. filename
end

--- Load an XML view and execute a Lua module file from a ZIP archive.
-- @param pkgName    Package filename/absolute path (e.g. "hello.blpkg" or "/full/path/x.zip")
-- @param xmlFile    Filename of the XML inside the ZIP (e.g. "hello.xml")
-- @param luaFile    Filename of the Lua file inside the ZIP, or nil
-- @return view, module
function zip_view_loader.load(pkgName, xmlFile, luaFile)
    local zipPath = resolvePkgPath(pkgName)
    local pkg = brls.ZipPackage.open(zipPath)
    if not pkg then
        print("[ZipViewLoader] ERROR: Cannot open ZIP: " .. tostring(zipPath))
        return nil, nil
    end

    -- Load the XML view
    local view = nil
    if xmlFile then
        view = pkg:loadXMLView(xmlFile)
        if not view then
            print("[ZipViewLoader] ERROR: Cannot load XML '" .. xmlFile .. "' from " .. zipPath)
            return nil, nil
        end
    end

    -- Load and execute the Lua module (optional)
    local module = nil
    if luaFile then
        module = pkg:requireLua(luaFile)
        if not module then
            print("[ZipViewLoader] ERROR: Cannot load Lua '" .. luaFile .. "' from " .. zipPath)
        end
    end

    return view, module
end

--- List all files inside a ZIP archive.
-- @param pkgName    Package filename or absolute path
-- @return table     List of filenames, or nil on failure
function zip_view_loader.listFiles(pkgName)
    local pkg = brls.ZipPackage.open(resolvePkgPath(pkgName))
    if not pkg then return nil end
    return pkg:listFiles()
end

--- Read a raw file from a ZIP archive.
-- @param pkgName    Package filename or absolute path
-- @param filename   Filename inside the ZIP
-- @return string    File content, or nil on failure
function zip_view_loader.readFile(pkgName, filename)
    local pkg = brls.ZipPackage.open(resolvePkgPath(pkgName))
    if not pkg then return nil end
    local content = pkg:readFile(filename)
    return content ~= "" and content or nil
end

return zip_view_loader
