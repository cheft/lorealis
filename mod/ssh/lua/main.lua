local _modPath = "mod/ssh/lua/"
if BRLS_RESOURCES and BRLS_RESOURCES == "romfs:/" then
    _modPath = "romfs:/mod/ssh/lua/"
end
package.path = package.path .. ";" .. _modPath .. "?.lua" .. ";" .. _modPath .. "?/init.lua"

local ssh_client_view = require("ssh_client_view")

return {
    show = function()
        ssh_client_view.showActivity()
    end,
    cleanup = function()
    end,
}
