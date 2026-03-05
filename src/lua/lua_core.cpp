#include "lua_manager.hpp"
#include "xml_loader.hpp"
#include "zip_loader.hpp"
#include <borealis/core/i18n.hpp>
#include <borealis/core/activity.hpp>
#include <borealis/core/view.hpp>
#include <fstream>
#include <filesystem>

void LuaManager::registerCoreBindings(sol::table& brls_ns) {
    // Enums
    brls_ns["Visibility"] = lua.create_table_with(
        "VISIBLE", brls::Visibility::VISIBLE,
        "GONE", brls::Visibility::GONE,
        "INVISIBLE", brls::Visibility::INVISIBLE
    );

    brls_ns["ControllerButton"] = lua.create_table_with(
        "BUTTON_A", brls::ControllerButton::BUTTON_A,
        "BUTTON_B", brls::ControllerButton::BUTTON_B,
        "BUTTON_X", brls::ControllerButton::BUTTON_X,
        "BUTTON_Y", brls::ControllerButton::BUTTON_Y,
        "BUTTON_LSB", brls::ControllerButton::BUTTON_LSB,
        "BUTTON_RSB", brls::ControllerButton::BUTTON_RSB,
        "BUTTON_LT", brls::ControllerButton::BUTTON_LT,
        "BUTTON_RT", brls::ControllerButton::BUTTON_RT,
        "BUTTON_LB", brls::ControllerButton::BUTTON_LB,
        "BUTTON_RB", brls::ControllerButton::BUTTON_RB,
        "BUTTON_UP", brls::ControllerButton::BUTTON_UP,
        "BUTTON_DOWN", brls::ControllerButton::BUTTON_DOWN,
        "BUTTON_LEFT", brls::ControllerButton::BUTTON_LEFT,
        "BUTTON_RIGHT", brls::ControllerButton::BUTTON_RIGHT,
        "BUTTON_START", brls::ControllerButton::BUTTON_START,
        "BUTTON_BACK", brls::ControllerButton::BUTTON_BACK,
        "BUTTON_GUIDE", brls::ControllerButton::BUTTON_GUIDE
    );

    brls_ns["HorizontalAlign"] = lua.create_table_with(
        "LEFT", brls::HorizontalAlign::LEFT,
        "CENTER", brls::HorizontalAlign::CENTER,
        "RIGHT", brls::HorizontalAlign::RIGHT
    );

    brls_ns["VerticalAlign"] = lua.create_table_with(
        "BASELINE", brls::VerticalAlign::BASELINE,
        "TOP", brls::VerticalAlign::TOP,
        "CENTER", brls::VerticalAlign::CENTER,
        "BOTTOM", brls::VerticalAlign::BOTTOM
    );

    brls_ns["ThemeVariant"] = lua.create_table_with(
        "LIGHT", brls::ThemeVariant::LIGHT,
        "DARK", brls::ThemeVariant::DARK
    );

    brls_ns["Axis"] = lua.create_table_with(
        "ROW", brls::Axis::ROW,
        "COLUMN", brls::Axis::COLUMN
    );

    // Application
    auto app = brls_ns["Application"].get_or_create<sol::table>();
    app["createWindow"] = [](const std::string& title) {
        return brls::Application::createWindow(title);
    };
    app["loadFontFromFile"] = [](const std::string& fontName, const std::string& filePath) {
        return brls::Application::loadFontFromFile(fontName, filePath);
    };
    app["addFontFallback"] = [](const std::string& fontName, const std::string& fallbackFontName) {
        brls::Application::addFontFallback(fontName, fallbackFontName);
    };
    app["pushActivity"] = sol::overload(
        [](brls::View* view) {
            brls::Application::pushActivity(new brls::Activity(view));
        },
        [](brls::Dropdown* dropdown) {
            brls::Application::pushActivity(new brls::Activity(dropdown));
        }
    );
    app["popActivity"] = []() {
        brls::Application::popActivity(brls::TransitionAnimation::FADE);
    };
    app["notify"] = [](const std::string& text) {
        brls::Application::notify(text);
    };
    app["getPlatform"] = []() { return brls::Application::getPlatform(); };
    app["getFPS"] = []() { return brls::Application::getFPS(); };
    app["getWindowSizeChangedEvent"] = [this]() -> brls::VoidEvent* {
        return brls::Application::getWindowSizeChangedEvent();
    };
    app["setLimitedFPS"] = [](int fps) { brls::Application::setLimitedFPS(fps); };
    app["getCurrentFocus"] = []() { return brls::Application::getCurrentFocus(); };
    app["getFPSStatus"] = []() { return brls::Application::getFPSStatus(); };
    app["setFPSStatus"] = [](bool value) { brls::Application::setFPSStatus(value); };
    app["enableDebuggingView"] = [](bool value) { brls::Application::enableDebuggingView(value); };
    app["isDebuggingViewEnabled"] = []() { return brls::Application::isDebuggingViewEnabled(); };
    app["setSwapInterval"] = [](int value) { brls::Application::setSwapInterval(value); };
    app["setGlobalQuit"] = [](bool value) { brls::Application::setGlobalQuit(value); };
    app["getActivitiesStack"] = []() { return brls::Application::getActivitiesStack(); };
    app["loadXML"] = [this](const std::string& path) {
        return this->pushView(XMLLoader::load(path));
    };
    app["loadXMLRes"] = [this](const std::string& path) {
        return this->pushView(XMLLoader::load(std::string(BRLS_RESOURCES) + path));
    };
    app["getAppletFrame"] = [this]() -> sol::object {
        auto stack = brls::Application::getActivitiesStack();
        if (stack.empty()) return sol::make_object(lua, sol::nil);
        return this->pushView(dynamic_cast<brls::AppletFrame*>(stack.back()->getContentView()));
    };
    app["registerXMLView"] = sol::overload(
        [](const std::string& name, const std::string& xmlResourcePath) {
            brls::Application::registerXMLView(name, [xmlResourcePath]() -> brls::View* {
                return XMLLoader::loadResource(xmlResourcePath);
            });
        },
        [](const std::string& name, sol::protected_function factory) {
            brls::Application::registerXMLView(name, [name, factory]() -> brls::View* {
                auto res = factory();
                if (!res.valid()) {
                    sol::error err = res;
                    brls::Logger::error("Lua error in registerXMLView factory '{}': {}", name, err.what());
                    return nullptr;
                }
                sol::object ret = res;
                if (ret.is<brls::View*>()) return ret.as<brls::View*>();
                return nullptr;
            });
        }
    );
    app["windowWidth"] = []() { return brls::Application::windowWidth; };
    app["windowHeight"] = []() { return brls::Application::windowHeight; };
    app["getWindowScale"] = []() { return brls::Application::windowScale; };
    app["setWindowScale"] = [](float scale) {
        brls::Application::windowScale = scale;
        // Force a layout recalculation by getting the activities stack and invalidating
        auto activities = brls::Application::getActivitiesStack();
        for (auto* activity : activities) {
            if (activity && activity->getContentView()) {
                activity->getContentView()->invalidate();
            }
        }
    };

    // Styling & Theming
    brls_ns["nvgRGB"] = sol::overload(
        [](int r, int g, int b) { return nvgRGB((unsigned char)r, (unsigned char)g, (unsigned char)b); },
        [](float r, float g, float b) { return nvgRGBf(r, g, b); }
    );
    brls_ns["nvgRGBA"] = sol::overload(
        [](int r, int g, int b, int a) { return nvgRGBA((unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a); },
        [](float r, float g, float b, float a) { return nvgRGBAf(r, g, b, a); }
    );

    // NanoVG Transforms (using void* to avoid C2139 on incomplete NVGcontext)
    brls_ns["nvgSave"]      = [](void* vg) { nvgSave((NVGcontext*)vg); };
    brls_ns["nvgRestore"]   = [](void* vg) { nvgRestore((NVGcontext*)vg); };
    brls_ns["nvgTranslate"] = [](void* vg, float x, float y) { nvgTranslate((NVGcontext*)vg, x, y); };
    brls_ns["nvgRotate"]    = [](void* vg, float angle) { nvgRotate((NVGcontext*)vg, angle); };
    brls_ns["nvgSkewX"]     = [](void* vg, float angle) { nvgSkewX((NVGcontext*)vg, angle); };
    brls_ns["nvgSkewY"]     = [](void* vg, float angle) { nvgSkewY((NVGcontext*)vg, angle); };
    brls_ns["nvgScale"]     = [](void* vg, float x, float y) { nvgScale((NVGcontext*)vg, x, y); };
    brls_ns["nvgText"]      = [](void* vg, float x, float y, const std::string& text) { 
        nvgText((NVGcontext*)vg, x, y, text.c_str(), nullptr); 
    };

    // VoidEvent for window size change, etc.
    auto void_event_ut = brls_ns.new_usertype<brls::VoidEvent>("VoidEvent", sol::no_construction());
    void_event_ut["subscribe"] = [](brls::VoidEvent& self, sol::protected_function func) {
        self.subscribe([func]() {
            if (func.valid()) {
                auto res = func();
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua VoidEvent error: {}", err.what()); }
            }
        });
    };
    void_event_ut["clear"] = &brls::VoidEvent::clear;

    auto theme_values_ut = brls_ns.new_usertype<brls::Theme>("Theme", sol::no_construction());
    theme_values_ut["addColor"] = &brls::Theme::addColor;
    theme_values_ut["getColor"] = &brls::Theme::getColor;
    theme_values_ut["getLightTheme"] = &brls::Theme::getLightTheme;
    theme_values_ut["getDarkTheme"] = &brls::Theme::getDarkTheme;

    auto style_ut = brls_ns.new_usertype<brls::Style>("Style", sol::no_construction());
    style_ut["addMetric"] = &brls::Style::addMetric;
    style_ut["getMetric"] = &brls::Style::getMetric;
    brls_ns["getStyle"] = &brls::getStyle;

    // i18n
    brls_ns["i18n"] = sol::overload(
        [](const std::string& key) { return brls::getStr(key); }
    );

    // Timers
    brls_ns["delay"] = [](long ms, sol::protected_function cb) {
        return brls::delay(ms, [cb]() {
            if (cb.valid()) {
                auto res = cb();
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua delay error: {}", err.what()); }
            }
        });
    };
    brls_ns["cancelDelay"] = [](size_t id) {
        brls::cancelDelay(id);
    };

    // Dialog
    auto dialog_ut = brls_ns.new_usertype<brls::Dialog>("Dialog",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::Box, brls::View>()
    );
    dialog_ut["new"] = [](const std::string& text) {
        return new brls::Dialog(text);
    };
    dialog_ut["addButton"] = [](brls::Dialog& self, const std::string& label, sol::protected_function cb) {
        self.addButton(label, [label, cb]() {
            brls::Logger::info("Dialog button '{}' clicked", label);
            if (cb.valid()) {
                auto res = cb();
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in Dialog button: {}", err.what()); }
            }
        });
    };
    dialog_ut["open"] = &brls::Dialog::open;
    dialog_ut["close"] = &brls::Dialog::close;

    // Activity
    auto activity_ut = brls_ns.new_usertype<brls::Activity>("Activity", sol::no_construction());
    activity_ut["getContentView"] = [this](brls::Activity& self) {
        return this->pushView(self.getContentView());
    };

    activity_ut["getContentView"] = [this](brls::Activity& self) {
        return this->pushView(self.getContentView());
    };

    // Static Bottom Bar visibility control
    brls_ns["getHideBottomBar"] = []() { 
        return (bool)brls::AppletFrame::HIDE_BOTTOM_BAR; 
    };
    brls_ns["setHideBottomBar"] = [](bool value) { 
        brls::AppletFrame::HIDE_BOTTOM_BAR = value; 
        brls::Logger::info("HIDE_BOTTOM_BAR set to {}", value);
    };

    // Platform
    auto platform_ut = brls_ns.new_usertype<brls::Platform>("Platform", sol::no_construction());
    platform_ut["getName"] = &brls::Platform::getName;
    platform_ut["getIpAddress"] = &brls::Platform::getIpAddress;
    platform_ut["getDnsServer"] = &brls::Platform::getDnsServer;
    platform_ut["isScreenDimmingDisabled"] = &brls::Platform::isScreenDimmingDisabled;
    platform_ut["disableScreenDimming"] = [](brls::Platform& self, bool disable) {
        self.disableScreenDimming(disable);
    };
    platform_ut["setWindowAlwaysOnTop"] = &brls::Platform::setWindowAlwaysOnTop;
    platform_ut["setWindowSize"] = &brls::Platform::setWindowSize;
    platform_ut["getBacklightBrightness"] = &brls::Platform::getBacklightBrightness;
    platform_ut["setBacklightBrightness"] = &brls::Platform::setBacklightBrightness;
    platform_ut["openBrowser"] = &brls::Platform::openBrowser;
    platform_ut["getThemeVariant"] = &brls::Platform::getThemeVariant;
    platform_ut["setThemeVariant"] = &brls::Platform::setThemeVariant;
    platform_ut["readFile"] = [](brls::Platform& self, const std::string& path) -> std::string {
        std::ifstream file(path);
        if (!file.is_open()) return "";
        std::stringstream buffer;
        buffer << file.rdbuf();
        return buffer.str();
    };
    platform_ut["writeFile"] = [](brls::Platform& self, const std::string& path, const std::string& content) -> bool {
        std::ofstream file(path);
        if (!file.is_open()) return false;
        file << content;
        return true;
    };
    platform_ut["mkdir"] = [](brls::Platform& self, const std::string& path) -> bool {
        try {
            return std::filesystem::create_directories(path);
        } catch (...) {
            return false;
        }
    };

    // ============================================================
    // ZipPackage: brls.ZipPackage.open("/abs/path/to/pkg.zip")
    // ============================================================
    auto zip_ut = brls_ns.new_usertype<ZipLoader>("ZipPackage",
        sol::no_construction()
    );

    // Static factory: brls.ZipPackage.open(path) -> ZipPackage or nil
    zip_ut["open"] = [](const std::string& path) -> std::shared_ptr<ZipLoader> {
        auto loader = std::make_shared<ZipLoader>(path);
        if (!loader->isOpen()) return nullptr;
        return loader;
    };

    // Check if a file exists inside the ZIP
    zip_ut["hasFile"] = [](ZipLoader& self, const std::string& name) {
        return self.hasFile(name);
    };

    // List all entries in the ZIP
    zip_ut["listFiles"] = [](ZipLoader& self) {
        return self.listFiles();
    };

    // Get raw content of a file as a string
    zip_ut["readFile"] = [](ZipLoader& self, const std::string& name) {
        return self.readFile(name);
    };

    // Load an XML file from the ZIP and return the created brls::View
    zip_ut["loadXMLView"] = [this](ZipLoader& self, const std::string& xmlName) -> sol::object {
        std::string content = self.readFile(xmlName);
        if (content.empty()) {
            brls::Logger::error("ZipPackage.loadXMLView: '{}' is empty or not found", xmlName);
            return sol::make_object(lua, sol::nil);
        }
        brls::View* view = brls::View::createFromXMLString(content);
        if (!view) {
            brls::Logger::error("ZipPackage.loadXMLView: Failed to create view from '{}'", xmlName);
            return sol::make_object(lua, sol::nil);
        }
        // Register all subviews so getView() works in Lua
        std::function<void(brls::View*)> reg = [&](brls::View* v) {
            if (!v) return;
            LuaManager::getInstance().registerView(v);
            if (auto* b = dynamic_cast<brls::Box*>(v))
                for (auto* c : b->getChildren()) reg(c);
        };
        reg(view);
        return this->pushView(view);
    };

    // Load and execute a Lua file from the ZIP; returns the module table
    zip_ut["requireLua"] = [this](ZipLoader& self, const std::string& luaName) -> sol::object {
        std::string code = self.readFile(luaName);
        if (code.empty()) {
            brls::Logger::error("ZipPackage.requireLua: '{}' is empty or not found", luaName);
            return sol::make_object(lua, sol::nil);
        }
        // Give the chunk a meaningful name for error messages
        std::string chunkName = "@" + luaName;
        sol::load_result chunk = lua.load(code, chunkName, sol::load_mode::text);
        if (!chunk.valid()) {
            sol::error err = chunk;
            brls::Logger::error("ZipPackage.requireLua: Syntax error in '{}': {}", luaName, err.what());
            return sol::make_object(lua, sol::nil);
        }
        sol::protected_function_result result = chunk();
        if (!result.valid()) {
            sol::error err = result;
            brls::Logger::error("ZipPackage.requireLua: Runtime error in '{}': {}", luaName, err.what());
            return sol::make_object(lua, sol::nil);
        }
        return result;
    };
}
