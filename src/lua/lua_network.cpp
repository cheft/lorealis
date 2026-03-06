#include "lua_manager.hpp"
#include "network/http_client.hpp"
#include <borealis/core/logger.hpp>

using namespace brls;

void LuaManager::registerNetworkBindings(sol::table& brls_ns) {
    auto network = brls_ns["Network"].get_or_create<sol::table>();
    
    network["get"] = [](const std::string& url, sol::protected_function callback) {
        return SimpleHTTPClient::get(url, [callback](bool success, int statusCode, const std::string& response) {
            if (callback.valid()) {
                auto res = callback(success, statusCode, response);
                if (!res.valid()) {
                    sol::error err = res;
                    brls::Logger::warning("Lua error in Network.get callback: {}", err.what());
                }
            }
        });
    };

    network["downloadImage"] = [](const std::string& url, sol::protected_function callback) {
        return SimpleHTTPClient::downloadImage(url, [callback](bool success, const std::string& data) {
            if (callback.valid()) {
                auto res = callback(success, data);
                if (!res.valid()) {
                    sol::error err = res;
                    brls::Logger::error("Lua error in Network.downloadImage callback: {}", err.what());
                }
            }
        });
    };

    network["cancel"] = [](uint32_t id) {
        NetworkRegistry::cancel(id);
    };
}
