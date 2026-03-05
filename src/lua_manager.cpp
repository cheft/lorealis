#include "lua_manager.hpp"
#include "lua/lua_bindings.hpp"
#include <borealis/views/applet_frame.hpp>
#include <borealis/views/scrolling_frame.hpp>
#include <borealis/views/cells/cell_bool.hpp>
#include <borealis/views/cells/cell_radio.hpp>
#include <borealis/views/cells/cell_selector.hpp>
#include <borealis/views/cells/cell_slider.hpp>
#include <borealis/views/cells/cell_input.hpp>
#include "view/html_renderer.hpp"

bool LuaManager::init() {
    try {
        lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::string, sol::lib::table, sol::lib::math, sol::lib::os, sol::lib::debug);
        
        // Initialize globals
        lua["views"] = lua.create_table();
        
        registerBorealisBindings();
        return true;
    } catch (const std::exception& e) {
        brls::Logger::error("Failed to initialize Lua: {}", e.what());
        return false;
    }
}

void LuaManager::deinit() {
}

bool LuaManager::doFile(const std::string& path) {
    auto result = lua.script_file(path);
    if (!result.valid()) {
        sol::error err = result;
        brls::Logger::error("Lua error loading {}: {}", path, err.what());
        return false;
    }
    return true;
}

bool LuaManager::doString(const std::string& script) {
    auto result = lua.script(script);
    if (!result.valid()) {
        sol::error err = result;
        brls::Logger::error("Lua error: {}", err.what());
        return false;
    }
    return true;
}

void LuaManager::registerBorealisBindings() {
    auto brls_ns = lua["brls"].get_or_create<sol::table>();

    registerCoreBindings(brls_ns);
    registerViewBindings(brls_ns);
    registerAnimationBindings(brls_ns);
    registerRecyclerBindings(brls_ns);
    registerCellBindings(brls_ns);
    registerNetworkBindings(brls_ns);
    registerHtmlBindings(brls_ns);
}

void LuaManager::registerView(brls::View* view) {
    if (!view) return;
    std::string id = view->getId();
    if (id.empty()) return;

    lua["views"][id] = pushView(view);
}

sol::object LuaManager::pushView(brls::View* view) {
    if (!view) return sol::make_object(lua, sol::nil);

    if (auto* icell = dynamic_cast<brls::InputCell*>(view)) return sol::make_object(lua, icell);
    if (auto* incell = dynamic_cast<brls::InputNumericCell*>(view)) return sol::make_object(lua, incell);
    if (auto* slcell = dynamic_cast<brls::SelectorCell*>(view)) return sol::make_object(lua, slcell);
    if (auto* bcell = dynamic_cast<brls::BooleanCell*>(view)) return sol::make_object(lua, bcell);
    if (auto* scell = dynamic_cast<brls::SliderCell*>(view)) return sol::make_object(lua, scell);
    if (auto* rcell = dynamic_cast<brls::RadioCell*>(view)) return sol::make_object(lua, rcell);
    if (auto* dcell = dynamic_cast<brls::DetailCell*>(view)) return sol::make_object(lua, dcell);

    if (auto* recyclerCell = dynamic_cast<brls::RecyclerCell*>(view)) return sol::make_object(lua, recyclerCell);
    if (auto* recycler = dynamic_cast<brls::RecyclerFrame*>(view)) return sol::make_object(lua, recycler);
    
    if (auto* frame = dynamic_cast<brls::AppletFrame*>(view)) return sol::make_object(lua, frame);
    if (auto* scroll = dynamic_cast<brls::ScrollingFrame*>(view)) return sol::make_object(lua, scroll);
    
    if (auto* button = dynamic_cast<brls::Button*>(view)) return sol::make_object(lua, button);
    if (auto* slider = dynamic_cast<brls::Slider*>(view)) return sol::make_object(lua, slider);
    
    if (auto* box = dynamic_cast<brls::Box*>(view)) return sol::make_object(lua, box);

    if (auto* luaImage = dynamic_cast<LuaImage*>(view)) return sol::make_object(lua, luaImage);
    if (auto* image = dynamic_cast<brls::Image*>(view)) return sol::make_object(lua, image);
    if (auto* label = dynamic_cast<brls::Label*>(view)) return sol::make_object(lua, label);
    if (auto* html = dynamic_cast<brls::HtmlRenderer*>(view)) return sol::make_object(lua, html);
    
    return sol::make_object(lua, view);
}
