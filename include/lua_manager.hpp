#pragma once

#include <sol/sol.hpp>
#include <borealis.hpp>
#include <string>
#include <functional>

class LuaManager {
public:
    static LuaManager& getInstance() {
        static LuaManager instance;
        return instance;
    }

    bool init();
    void deinit();

    // Load and execute a lua script
    bool doFile(const std::string& path);
    bool doString(const std::string& lua);

    // Call a lua function
    template<typename... Args>
    void call(const std::string& name, Args&&... args) {
        sol::function func = lua[name];
        if (func.valid()) {
            auto result = func(std::forward<Args>(args)...);
            if (!result.valid()) {
                sol::error err = result;
                brls::Logger::error("Lua error calling {}: {}", name, err.what());
            }
        }
    }

    sol::state& getLuaState() { return lua; }

    // Register a view in the lua context
    void registerView(brls::View* view);

    // Push a view to Lua as its specific derived type
    sol::object pushView(brls::View* view);

    // Bindings initialization
    void registerCoreBindings(sol::table& brls_ns);
    void registerViewBindings(sol::table& brls_ns);
    void registerCellBindings(sol::table& brls_ns);
    void registerAnimationBindings(sol::table& brls_ns);
    void registerRecyclerBindings(sol::table& brls_ns);
    void registerNetworkBindings(sol::table& brls_ns);
    void registerHtmlBindings(sol::table& brls_ns);

private:
    LuaManager() = default;
    ~LuaManager() = default;

    sol::state lua;

    void registerBorealisBindings();
};
