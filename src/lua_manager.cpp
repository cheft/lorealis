#include "lua_manager.hpp"
#include "lua/lua_bindings.hpp"
#include "ns_log.hpp"
#include <borealis/views/applet_frame.hpp>
#include <borealis/views/scrolling_frame.hpp>
#include <borealis/views/cells/cell_bool.hpp>
#include <borealis/views/cells/cell_radio.hpp>
#include <borealis/views/cells/cell_selector.hpp>
#include <borealis/views/cells/cell_slider.hpp>
#include <borealis/views/cells/cell_input.hpp>
#include "view/html_renderer.hpp"
#include "view/markdown_renderer.hpp"

bool LuaManager::init() {
    try {
        NS_LOG("BRLS: LuaManager::init() - opening Lua libraries...");
        lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::string, sol::lib::table, sol::lib::math, sol::lib::os, sol::lib::debug);
        NS_LOG("BRLS: LuaManager::init() - Lua libraries opened OK");
        
        // Initialize globals
        lua["views"] = lua.create_table();
        
        NS_LOG("BRLS: LuaManager::init() - registering Borealis bindings...");
        registerBorealisBindings();
        NS_LOG("BRLS: LuaManager::init() - all bindings registered OK");
        return true;
    } catch (const std::exception& e) {
        NS_LOG("BRLS: LuaManager::init() CRASH: %s", e.what());
        reportError("Failed to initialize Lua: " + std::string(e.what()));
        return false;
    }
}

void LuaManager::reportError(const std::string& message) {
    NS_LOG("BRLS: LuaManager ERROR: %s", message.c_str());
    brls::Logger::error("{}", message);
    
    // Show a dialog on the UI thread
    brls::Application::blockInputs();
    brls::Dialog* dialog = new brls::Dialog(message);
    dialog->addButton("OK", []() {
        brls::Application::unblockInputs();
    });
    dialog->open();
}

void LuaManager::deinit() {
}

bool LuaManager::doFile(const std::string& path) {
    NS_LOG("BRLS: LuaManager::doFile(%s)", path.c_str());
    auto result = lua.script_file(path);
    if (!result.valid()) {
        sol::error err = result;
        NS_LOG("BRLS: LuaManager::doFile FAILED: %s", err.what());
        reportError("Lua error loading " + path + ": " + std::string(err.what()));
        return false;
    }
    NS_LOG("BRLS: LuaManager::doFile(%s) OK", path.c_str());
    return true;
}

bool LuaManager::doString(const std::string& script) {
    auto result = lua.script(script);
    if (!result.valid()) {
        sol::error err = result;
        NS_LOG("BRLS: LuaManager::doString FAILED: %s", err.what());
        reportError("Lua error: " + std::string(err.what()));
        return false;
    }
    return true;
}

// Macro to wrap each binding stage in try-catch with logging
#define REGISTER_STAGE(name, func) \
    NS_LOG("BRLS: [Bindings] Registering " name "..."); \
    try { func(brls_ns); NS_LOG("BRLS: [Bindings] " name " OK"); } \
    catch (const std::exception& e) { NS_LOG("BRLS: [Bindings] CRASH in " name ": %s", e.what()); throw; }

void LuaManager::registerBorealisBindings() {
    auto brls_ns = lua["brls"].get_or_create<sol::table>();

    REGISTER_STAGE("CoreBindings",      registerCoreBindings)
    REGISTER_STAGE("ViewBindings",      registerViewBindings)
    REGISTER_STAGE("AnimationBindings", registerAnimationBindings)
    REGISTER_STAGE("RecyclerBindings",  registerRecyclerBindings)
    REGISTER_STAGE("CellBindings",      registerCellBindings)
    REGISTER_STAGE("NetworkBindings",   registerNetworkBindings)
    REGISTER_STAGE("HtmlBindings",      registerHtmlBindings)
    REGISTER_STAGE("SSHBindings",       registerSSHBindings)
}

#undef REGISTER_STAGE

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
    if (auto* md = dynamic_cast<brls::MarkdownRenderer*>(view)) return sol::make_object(lua, md);
    if (auto* html = dynamic_cast<brls::HtmlRenderer*>(view)) return sol::make_object(lua, html);
    
    return sol::make_object(lua, view);
}
