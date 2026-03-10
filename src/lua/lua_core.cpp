#include "lua_manager.hpp"
#include <nanovg.h>
#include "xml_loader.hpp"
#include "zip_loader.hpp"
#include "ns_log.hpp"
#include <borealis/core/i18n.hpp>
#include <borealis/core/activity.hpp>
#include <borealis/core/view.hpp>
#include <fstream>
#include <sys/stat.h>
#include <string>
#include <sstream>
#ifdef __SWITCH__
#include <switch.h>
#endif
#ifdef _WIN32
#include <direct.h>
#endif

// Cross-platform recursive mkdir (replaces std::filesystem::create_directories)
static bool portable_mkdirs(const std::string& path) {
    if (path.empty()) return false;
    std::string accum;
    std::istringstream ss(path);
    std::string token;
    // Handle leading '/' for absolute paths
    if (path[0] == '/') accum = "/";
    while (std::getline(ss, token, '/')) {
        if (token.empty()) continue;
        if (!accum.empty() && accum.back() != '/' && accum.back() != '\\') accum += '/';
        accum += token;
#ifdef _WIN32
        _mkdir(accum.c_str());
#else
        mkdir(accum.c_str(), 0755);
#endif
    }
    struct stat st;
    return (stat(path.c_str(), &st) == 0);
}

#ifdef __SWITCH__
static uint64_t poll_default_switch_buttons()
{
    static bool initialized = false;
    static PadState pad;

    if (!initialized)
    {
        padInitializeDefault(&pad);
        initialized = true;
    }

    padUpdate(&pad);
    return padGetButtons(&pad);
}

static uint64_t map_controller_button_to_switch_mask(int button)
{
    switch ((brls::ControllerButton)button)
    {
        case brls::BUTTON_A:
            return HidNpadButton_A;
        case brls::BUTTON_B:
            return HidNpadButton_B;
        case brls::BUTTON_X:
            return HidNpadButton_X;
        case brls::BUTTON_Y:
            return HidNpadButton_Y;
        case brls::BUTTON_LB:
            return HidNpadButton_L;
        case brls::BUTTON_RB:
            return HidNpadButton_R;
        case brls::BUTTON_LT:
            return HidNpadButton_ZL;
        case brls::BUTTON_RT:
            return HidNpadButton_ZR;
        case brls::BUTTON_LSB:
            return HidNpadButton_StickL;
        case brls::BUTTON_RSB:
            return HidNpadButton_StickR | HidNpadButton_R;
        case brls::BUTTON_UP:
        case brls::BUTTON_NAV_UP:
            return HidNpadButton_Up;
        case brls::BUTTON_RIGHT:
        case brls::BUTTON_NAV_RIGHT:
            return HidNpadButton_Right;
        case brls::BUTTON_DOWN:
        case brls::BUTTON_NAV_DOWN:
            return HidNpadButton_Down;
        case brls::BUTTON_LEFT:
        case brls::BUTTON_NAV_LEFT:
            return HidNpadButton_Left;
        case brls::BUTTON_START:
            return HidNpadButton_Plus;
        case brls::BUTTON_BACK:
            return HidNpadButton_Minus;
        default:
            return 0;
    }
}
#endif

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
    app["giveFocus"] = [](brls::View* view) { brls::Application::giveFocus(view); };
    app["notify"] = [](const std::string& text) {
        brls::Application::notify(text);
    };
    app["getControllerState"] = []() -> brls::ControllerState {
        return brls::Application::getControllerState();
    };
    app["isControllerButtonPressed"] = [](int button) -> bool {
        if (button < 0 || button >= brls::_BUTTON_MAX)
            return false;

        const auto& state = brls::Application::getControllerState();
        return state.buttons[button];
    };
    app["isSwitchControllerButtonPressed"] = [](int button) -> bool {
#ifdef __SWITCH__
        if (button < 0 || button >= brls::_BUTTON_MAX)
            return false;

        uint64_t mask = map_controller_button_to_switch_mask(button);
        if (mask == 0)
            return false;

        return (poll_default_switch_buttons() & mask) != 0;
#else
        (void)button;
        return false;
#endif
    };
    app["getSwitchButtonsDebug"] = []() -> std::string {
#ifdef __SWITCH__
        std::stringstream ss;
        ss << "0x" << std::hex << std::uppercase << poll_default_switch_buttons();
        return ss.str();
#else
        return "desktop";
#endif
    };
    app["getSwitchTouchState"] = [this]() -> sol::object {
#ifdef __SWITCH__
        HidTouchScreenState hidState;
        if (hidGetTouchScreenStates(&hidState, 1) && hidState.count > 0)
        {
            return sol::make_object(lua, lua.create_table_with(
                "pressed", true,
                "count", (int)hidState.count,
                "x", (float)hidState.touches[0].x / brls::Application::windowScale,
                "y", (float)hidState.touches[0].y / brls::Application::windowScale,
                "id", (int)hidState.touches[0].finger_id));
        }

        return sol::make_object(lua, lua.create_table_with(
            "pressed", false,
            "count", 0,
            "x", 0.0f,
            "y", 0.0f,
            "id", -1));
#else
        return sol::make_object(lua, lua.create_table_with(
            "pressed", false,
            "count", 0,
            "x", 0.0f,
            "y", 0.0f,
            "id", -1));
#endif
    };
    app["openTextIME"] = [](sol::protected_function cb,
        sol::optional<std::string> headerText,
        sol::optional<std::string> subText,
        sol::optional<int> maxStringLength,
        sol::optional<std::string> initialText,
        sol::optional<int> kbdDisableBitmask) -> bool {
        return brls::Application::getImeManager()->openForText(
            [cb](std::string text) {
                if (!cb.valid())
                    return;

                auto result = cb(text);
                if (!result.valid()) {
                    sol::error err = result;
                    brls::Logger::error("Lua error in Application.openTextIME: {}", err.what());
                }
            },
            headerText.value_or(""),
            subText.value_or(""),
            maxStringLength.value_or(256),
            initialText.value_or(""),
            kbdDisableBitmask.value_or(brls::KeyboardKeyDisableBitmask::KEYBOARD_DISABLE_NONE));
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
    brls_ns["nvgBeginPath"] = [](void* vg) { nvgBeginPath((NVGcontext*)vg); };
    brls_ns["nvgFill"]      = [](void* vg) { nvgFill((NVGcontext*)vg); };
    brls_ns["nvgRect"]      = [](void* vg, float x, float y, float w, float h) { nvgRect((NVGcontext*)vg, x, y, w, h); };
    brls_ns["nvgFillColor"] = [](void* vg, NVGcolor color) { nvgFillColor((NVGcontext*)vg, color); };
    brls_ns["nvgFontSize"]  = [](void* vg, float size) { nvgFontSize((NVGcontext*)vg, size); };
    brls_ns["nvgFontFace"]  = [](void* vg, const std::string& font) { nvgFontFace((NVGcontext*)vg, font.c_str()); };
    brls_ns["nvgTextAlign"] = [](void* vg, int align) { nvgTextAlign((NVGcontext*)vg, align); };
    brls_ns["nvgRoundedRect"] = [](void* vg, float x, float y, float w, float h, float r) { nvgRoundedRect((NVGcontext*)vg, x, y, w, h, r); };
    brls_ns["nvgMoveTo"]    = [](void* vg, float x, float y) { nvgMoveTo((NVGcontext*)vg, x, y); };
    brls_ns["nvgLineTo"]    = [](void* vg, float x, float y) { nvgLineTo((NVGcontext*)vg, x, y); };
    brls_ns["nvgStrokeColor"] = [](void* vg, NVGcolor color) { nvgStrokeColor((NVGcontext*)vg, color); };
    brls_ns["nvgStrokeWidth"] = [](void* vg, float size) { nvgStrokeWidth((NVGcontext*)vg, size); };
    brls_ns["nvgStroke"]      = [](void* vg) { nvgStroke((NVGcontext*)vg); };
    brls_ns["nvgFontBlur"]    = [](void* vg, float blur) { nvgFontBlur((NVGcontext*)vg, blur); };
    brls_ns["NVG_ALIGN_LEFT"]   = (int)NVG_ALIGN_LEFT;
    brls_ns["NVG_ALIGN_CENTER"] = (int)NVG_ALIGN_CENTER;
    brls_ns["NVG_ALIGN_RIGHT"]  = (int)NVG_ALIGN_RIGHT;
    brls_ns["NVG_ALIGN_TOP"]    = (int)NVG_ALIGN_TOP;
    brls_ns["NVG_ALIGN_MIDDLE"] = (int)NVG_ALIGN_MIDDLE;
    brls_ns["NVG_ALIGN_BOTTOM"] = (int)NVG_ALIGN_BOTTOM;

    // KeyState
    auto key_state_ut = brls_ns.new_usertype<brls::KeyState>("KeyState", sol::no_construction());
    key_state_ut["key"]     = &brls::KeyState::key;
    key_state_ut["mods"]    = &brls::KeyState::mods;
    key_state_ut["pressed"] = &brls::KeyState::pressed;

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

    // KeyStateEvent
    using KeyStateEvent = brls::Event<brls::KeyState>;
    auto key_state_event_ut = brls_ns.new_usertype<KeyStateEvent>("KeyStateEvent", sol::no_construction());
    key_state_event_ut["subscribe"] = [](KeyStateEvent& self, sol::protected_function cb) {
        self.subscribe([cb](brls::KeyState s) {
            if (cb.valid()) {
                auto res = cb(s);
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in KeyStateEvent: {}", err.what()); }
            }
        });
    };

    // CharInputEvent
    using CharInputEvent = brls::Event<unsigned int>;
    auto char_input_event_ut = brls_ns.new_usertype<CharInputEvent>("CharInputEvent", sol::no_construction());
    char_input_event_ut["subscribe"] = [](CharInputEvent& self, sol::protected_function cb) {
        self.subscribe([cb](unsigned int c) {
            if (cb.valid()) {
                auto res = cb(c);
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in CharInputEvent: {}", err.what()); }
            }
        });
    };

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
    dialog_ut["getAppletFrame"] = [this](brls::Dialog& self) {
        return this->pushView(self.getAppletFrame());
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
    platform_ut["getInputManager"] = &brls::Platform::getInputManager;
    
    // InputManager
    auto input_manager_ut = brls_ns.new_usertype<brls::InputManager>("InputManager", sol::no_construction());
    input_manager_ut["getKeyboardKeyStateChanged"] = &brls::InputManager::getKeyboardKeyStateChanged;
    input_manager_ut["getCharInputEvent"] = &brls::InputManager::getCharInputEvent;
    input_manager_ut["sendRumble"] = [](brls::InputManager& self, unsigned short controller, unsigned short lowFreqMotor, unsigned short highFreqMotor) {
        self.sendRumble(controller, lowFreqMotor, highFreqMotor);
    };

    auto controller_state_ut = brls_ns.new_usertype<brls::ControllerState>("ControllerState", sol::no_construction());
    controller_state_ut["isButtonPressed"] = [](const brls::ControllerState& self, int button) {
        if (button < 0 || button >= brls::_BUTTON_MAX)
            return false;
        return self.buttons[button];
    };
    controller_state_ut["getAxis"] = [](const brls::ControllerState& self, int axis) {
        if (axis < 0 || axis >= brls::_AXES_MAX)
            return 0.0f;
        return self.axes[axis];
    };
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
            return portable_mkdirs(path);
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
