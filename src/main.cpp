#include <borealis.hpp>
#include "lua_manager.hpp"
#include "xml_loader.hpp"
#include "ns_log.hpp"

#ifdef __SWITCH__
#include <switch.h>
#include <dirent.h>
#include <unistd.h>
#include <curl/curl.h>
#endif

int main(int argc, char* argv[]) {
    NS_LOG("BRLS: Application main() entered");

#ifdef __SWITCH__
    // CRITICAL: Mount romfs FIRST — all romfs:/ paths require this
    Result romfs_rc = romfsInit();
    if (R_FAILED(romfs_rc)) {
        NS_LOG("BRLS: FATAL: romfsInit() failed with rc=%u", romfs_rc);
    } else {
        NS_LOG("BRLS: romfsInit() succeeded");
    }

    // Initialize PL service so we can grab the system-provided fonts
    Result pl_rc = plInitialize(PlServiceType_User);
    if (R_FAILED(pl_rc)) {
        NS_LOG("BRLS: WARNING: plInitialize failed with rc=%u. Fonts might not load!", pl_rc);
    } else {
        NS_LOG("BRLS: plInitialize() succeeded");
    }

    curl_global_init(CURL_GLOBAL_ALL);
#endif

#ifdef __SWITCH__
    // Diagnostic: check if romfs is accessible
    DIR* dir = opendir("romfs:/");
    if (dir) {
        NS_LOG("BRLS: romfs:/ is accessible. Basic check passed.");
        closedir(dir);
        
        // Critical file checks
        const char* critical_files[] = {
            "romfs:/material/MaterialIcons-Regular.ttf",
            "romfs:/font/switch_font.ttf",
            "romfs:/i18n/en-US/hints.json"
        };
        
        for (const char* file : critical_files) {
            if (access(file, F_OK) != -1) {
                NS_LOG("BRLS: Found critical file: %s", file);
            } else {
                NS_LOG("BRLS: ERROR: Missing critical file: %s", file);
            }
        }
    } else {
        NS_LOG("BRLS: ERROR: romfs:/ is NOT accessible via opendir!");
    }
#endif

    try {
        // Initialize Borealis
        if (!brls::Application::init()) {
            NS_LOG("BRLS: Unable to init Borealis");
            return 1;
        }

        NS_LOG("BRLS: Application::init success");

        // Initialize Lua
        if (!LuaManager::getInstance().init()) {
            NS_LOG("BRLS: Unable to init Lua");
            return 1;
        }
        NS_LOG("BRLS: LuaManager::init success");

        // Configure package.path so 'require' can find our modules
        NS_LOG("BRLS: Setting up package.path...");
        std::string pkgPathSetup = 
            std::string("package.path = package.path .. ';") + 
            BRLS_RESOURCES + "lua/?.lua;" + 
            BRLS_RESOURCES + "lua/?/init.lua'";
        LuaManager::getInstance().doString(pkgPathSetup);
        NS_LOG("BRLS: package.path configured OK");

        // Load main.lua
        NS_LOG("BRLS: Loading main.lua...");
        LuaManager::getInstance().doFile(std::string(BRLS_RESOURCES) + "lua/main.lua");
        NS_LOG("BRLS: main.lua loaded OK");

        // Let Lua handle everything (XML loading and UI orchestration)
        NS_LOG("BRLS: Calling Lua onInit()...");
        LuaManager::getInstance().call("onInit");
        NS_LOG("BRLS: Lua onInit() returned OK, entering main loop...");

        // Main Loop
        while (brls::Application::mainLoop()) {
            // Borealis handles the rest
        }
    } catch (const std::exception& e) {
        NS_LOG("BRLS: CRASH - std::exception: %s", e.what());
    } catch (...) {
        NS_LOG("BRLS: CRASH - Unknown exception");
    }

    NS_LOG("BRLS: Application main() exiting normally");
#ifdef __SWITCH__
    curl_global_cleanup();
    plExit();
    romfsExit();
#endif
    return 0;
}
