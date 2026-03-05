#include <borealis.hpp>
#include "lua_manager.hpp"
#include "xml_loader.hpp"
#include <cstdio>
#include <stdarg.h>

#ifdef __SWITCH__
#include <dirent.h>
#include <unistd.h>
#include <curl/curl.h>
#endif

void NS_LOG(const char* format, ...)
{
    char buffer[512];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    // 1. Console
    printf("%s\n", buffer);
    fflush(stdout);
    
    // 2. SD Card
    FILE* f = fopen("sdmc:/brls.log", "a");
    if (f) {
        fprintf(f, "%s\n", buffer);
        fclose(f);
    }
}

int main(int argc, char* argv[]) {
    NS_LOG("BRLS: Application main() entered");

#ifdef __SWITCH__
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
        std::string pkgPathSetup = 
            std::string("package.path = package.path .. ';") + 
            BRLS_RESOURCES + "lua/?.lua;" + 
            BRLS_RESOURCES + "lua/?/init.lua'";
        LuaManager::getInstance().doString(pkgPathSetup);

        // Load main.lua
        LuaManager::getInstance().doFile(std::string(BRLS_RESOURCES) + "lua/main.lua");

        // Let Lua handle everything (XML loading and UI orchestration)
        NS_LOG("BRLS: Calling Lua onInit()...");
        LuaManager::getInstance().call("onInit");

        // NS_LOG("BRLS: Activity pushed, entering main loop");

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
#endif
    return 0;
}
