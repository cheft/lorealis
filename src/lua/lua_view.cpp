#include "lua_manager.hpp"
#include <borealis.hpp>
#include "lua_bindings.hpp"
#include "utils/image_utils.hpp"
#include <nanovg.h>
#include <borealis/views/label.hpp>
#include <borealis/views/scrolling_frame.hpp>
#include <borealis/views/applet_frame.hpp>

void LuaManager::registerViewBindings(sol::table& brls_ns) {
    // View
    auto view_ut = brls_ns.new_usertype<brls::View>("View", 
        sol::no_construction()
    );
    view_ut["setId"] = &brls::View::setId;
    view_ut["getId"] = &brls::View::getId;
    view_ut["get_address"] = [](brls::View& self) {
        return (uintptr_t)&self;
    };
    view_ut["getView"] = [this](sol::stack_object self, sol::stack_object id) -> sol::object {
        brls::View* view = nullptr;
        if (self.is<brls::View*>()) view = self.as<brls::View*>();
        
        if (!view) {
            brls::Logger::error("Lua: getView failed, 'self' is not a View! type: {}", (int)self.get_type());
            if (self.is<std::string>()) brls::Logger::error("Lua: 'self' value: '{}'", self.as<std::string>());
            return sol::make_object(lua, sol::nil);
        }
        
        if (!id.is<std::string>()) {
            brls::Logger::error("Lua: getView failed, 'id' is not a string! type: {}", (int)id.get_type());
            return sol::make_object(lua, sol::nil);
        }
        
        return this->pushView(view->getView(id.as<std::string>()));
    };
    view_ut["getParent"] = [this](brls::View& self) {
        return this->pushView(self.getParent());
    };
    view_ut["invalidate"] = &brls::View::invalidate;
    view_ut["setVisibility"] = &brls::View::setVisibility;
    view_ut["setWidth"] = &brls::View::setWidth;
    view_ut["setHeight"] = &brls::View::setHeight;
    view_ut["setTranslationX"] = &brls::View::setTranslationX;
    view_ut["setTranslationY"] = &brls::View::setTranslationY;
    view_ut["setBackgroundColor"] = &brls::View::setBackgroundColor;
    view_ut["setMarginTop"] = &brls::View::setMarginTop;
    view_ut["setMarginRight"] = &brls::View::setMarginRight;
    view_ut["setMarginBottom"] = &brls::View::setMarginBottom;
    view_ut["setMarginLeft"] = &brls::View::setMarginLeft;
    view_ut["setMargins"] = [](brls::View& self, float top, float right, float bottom, float left) {
        self.setMargins(top, right, bottom, left);
    };
    view_ut["registerAction"] = [this](brls::View& self, const std::string& hint, int button, sol::protected_function func) {
        self.registerAction(hint, (brls::ControllerButton)button, [this, func](brls::View* v) {
            auto result = func(this->pushView(v));
            if (!result.valid()) {
                sol::error err = result;
                brls::Logger::error("Lua error in registerAction: {}", err.what());
                return false;
            }
            if (result.get_type() != sol::type::boolean) return false;
            return result.get<bool>();
        });
    };
    view_ut["onFocusGained"] = [this](brls::View& self, sol::protected_function func) {
        // Clear existing subscriptions to prevent accumulation on repeated calls
        self.getFocusEvent()->clear();
        self.getFocusEvent()->subscribe([this, func](brls::View* v) {
            auto res = func(this->pushView(v));
            if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in onFocusGained: {}", err.what()); }
        });
    };
    view_ut["onFocusLost"] = [this](brls::View& self, sol::protected_function func) {
        // Clear existing subscriptions to prevent accumulation on repeated calls
        self.getFocusLostEvent()->clear();
        self.getFocusLostEvent()->subscribe([this, func](brls::View* v) {
            auto res = func(this->pushView(v));
            if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in onFocusLost: {}", err.what()); }
        });
    };
    view_ut["onWillDisappear"] = [this](brls::View& self, sol::protected_function func) {
        // Clear existing subscriptions to prevent accumulation on repeated calls
        self.getWillDisappearEvent()->clear();
        self.getWillDisappearEvent()->subscribe([this, func](brls::View* v) {
            auto res = func(this->pushView(v));
            if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in onWillDisappear: {}", err.what()); }
        });
    };
    view_ut["addGestureRecognizer"] = [](brls::View& self, brls::GestureRecognizer* g) { self.addGestureRecognizer(g); };
    view_ut["present"] = [](brls::View& self, brls::View* view) {
        self.present(view);
    };
    view_ut["getClassString"] = &brls::View::getClassString;
    view_ut["dismiss"] = [](brls::View& self) { self.dismiss(); };

    // Box
    auto box_ut = brls_ns.new_usertype<brls::Box>("Box",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::View>()
    );
    box_ut["addView"] = sol::overload(
        [](brls::Box& self, brls::View* v) { self.addView(v); },
        [](brls::Box& self, brls::View* v, size_t pos) { self.addView(v, pos); }
    );
    box_ut["removeView"] = [](brls::Box& self, brls::View* v) { self.removeView(v); };
    box_ut["setAxis"] = [](brls::Box& self, int axis) { self.setAxis((brls::Axis)axis); };
    box_ut["getChildren"] = [](brls::Box& self) -> std::vector<brls::View*> { return self.getChildren(); };
    box_ut["setGap"] = &brls::Box::setGap;
    box_ut["setColumnGap"] = &brls::Box::setColumnGap;
    box_ut["setRowGap"] = &brls::Box::setRowGap;
    box_ut["setPadding"] = [](brls::Box& self, float p) { self.setPadding(p); };
    box_ut["setPaddingTop"] = &brls::Box::setPaddingTop;
    box_ut["setPaddingBottom"] = &brls::Box::setPaddingBottom;
    box_ut["setPaddingLeft"] = &brls::Box::setPaddingLeft;
    box_ut["setPaddingRight"] = &brls::Box::setPaddingRight;
    box_ut["forwardXMLAttribute"] = sol::overload(
        [](brls::Box& self, const std::string& attr, brls::View* target) { self.forwardXMLAttribute(attr, target); },
        [](brls::Box& self, const std::string& attr, brls::View* target, const std::string& targetAttr) { self.forwardXMLAttribute(attr, target, targetAttr); }
    );

    // Label
    auto label_ut = brls_ns.new_usertype<brls::Label>("Label",
        sol::factories(
            []() { return new brls::Label(); },
            [](std::string text) {
                brls::Label* lbl = new brls::Label();
                lbl->setText(text);
                return lbl;
            }
        ),
        sol::base_classes, sol::bases<brls::View>()
    );
    label_ut["setText"] = &brls::Label::setText;
    label_ut["getText"] = &brls::Label::getFullText;
    label_ut["setFontSize"] = &brls::Label::setFontSize;
    label_ut["setLineHeight"] = &brls::Label::setLineHeight;
    label_ut["setHorizontalAlign"] = [](brls::Label& self, int align) { self.setHorizontalAlign((brls::HorizontalAlign)align); };
    label_ut["setVerticalAlign"] = [](brls::Label& self, int align) { self.setVerticalAlign((brls::VerticalAlign)align); };
    label_ut["setTextColor"] = &brls::Label::setTextColor;
    label_ut["setSingleLine"] = &brls::Label::setSingleLine;
    brls_ns["Label"]["create"] = []() { return brls::Label::create(); };

    // Button
    auto button_ut = brls_ns.new_usertype<brls::Button>("Button",
        sol::factories(
            []() { return new brls::Button(); },
            [this](std::string text, sol::protected_function func) {
                brls::Button* btn = new brls::Button();
                btn->setText(text);
                btn->registerClickAction([this, func](brls::View* v) -> bool {
                    auto result = func(this->pushView(v));
                    if (!result.valid()) { sol::error err = result; brls::Logger::error("Lua error in onClick: {}", err.what()); return true; }
                    if (result.get_type() != sol::type::boolean) return true;
                    return result.get<bool>();
                });
                return btn;
            }
        ),
        sol::base_classes, sol::bases<brls::Box, brls::View>()
    );
    button_ut["setText"] = &brls::Button::setText;
    button_ut["getText"] = &brls::Button::getText;
    button_ut["setFontSize"] = &brls::Button::setFontSize;
    button_ut["onClick"] = [](brls::Button& self, sol::protected_function func) {
        self.registerClickAction([func](brls::View* v) -> bool {
            auto result = func(v);
            if (!result.valid()) { sol::error err = result; brls::Logger::error("Lua error in onClick: {}", err.what()); return true; }
            if (result.get_type() != sol::type::boolean) return true;
            return result.get<bool>();
        });
    };
    button_ut["registerAction"] = [](brls::Button& self, const std::string& hint, int button, sol::protected_function func) {
        self.registerAction(hint, (brls::ControllerButton)button, [func](brls::View* v) {
            auto result = func(v);
            if (!result.valid()) { sol::error err = result; brls::Logger::error("Lua error in button action: {}", err.what()); return false; }
            if (result.get_type() != sol::type::boolean) return false;
            return result.get<bool>();
        });
    };
    button_ut["setVisibility"] = [](brls::Button& self, brls::Visibility v) { self.setVisibility(v); };
    button_ut["getId"]         = [](brls::Button& self) { return self.getId(); };
    button_ut["setId"]         = [](brls::Button& self, const std::string& id) { self.setId(id); };

    // Image
    auto image_ut = brls_ns.new_usertype<brls::Image>("Image",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::View>()
    );
    image_ut["setImageFromRes"] = &brls::Image::setImageFromRes;
    image_ut["setImageFromMem"] = [](brls::Image& self, const std::string& data) {
        if (data.empty()) return;
        
        // Check if data is WebP and decode it
        if (brls::ImageUtils::isWebP(data)) {
            std::string rgba;
            int width, height;
            if (brls::ImageUtils::decodeWebP(data, rgba, width, height)) {
                NVGcontext* vg = brls::Application::getNVGContext();
                int texture = nvgCreateImageRGBA(vg, width, height, 0, (const unsigned char*)rgba.data());
                self.innerSetImage(texture);
                return;
            }
            brls::Logger::error("Lua: Failed to decode WebP image");
            return;
        }
        
        // For non-WebP images, use the standard loader
        self.setImageFromMem((const unsigned char*)data.data(), (int)data.size());
    };

    image_ut["setImageFromRGBA"] = [](brls::Image& self, const std::string& rgba, int w, int h) {
        if (!rgba.empty()) {
            NVGcontext* vg = brls::Application::getNVGContext();
            int texture = nvgCreateImageRGBA(vg, w, h, 0, (const unsigned char*)rgba.data());
            self.innerSetImage(texture);
        }
    };
    image_ut["draw"] = &brls::Image::draw;
    brls_ns["Image"]["create"] = []() { return brls::Image::create(); };

    // Gestures
    brls_ns.new_usertype<brls::GestureRecognizer>("GestureRecognizer", sol::no_construction());
    brls_ns["TapGestureRecognizer"] = lua.create_table();
    brls_ns["TapGestureRecognizer"]["new"] = [](brls::View* view, brls::TapGestureConfig config) -> brls::GestureRecognizer* {
        return new brls::TapGestureRecognizer(view, config);
    };
    brls_ns["TapGestureConfig"] = [](bool b1, int s1, int s2, int s3) {
        return brls::TapGestureConfig(b1, (brls::Sound)s1, (brls::Sound)s2, (brls::Sound)s3);
    };
    brls_ns["Sound"] = lua.create_table_with("NONE", brls::SOUND_NONE);

    // ScrollingFrame
    auto scrolling_frame_ut = brls_ns.new_usertype<brls::ScrollingFrame>("ScrollingFrame",
        sol::factories(
            []() { return new brls::ScrollingFrame(); }
        ),
        sol::base_classes, sol::bases<brls::Box, brls::View>()
    );
    scrolling_frame_ut["addView"] = [](brls::ScrollingFrame& self, brls::View* v) { self.addView(v); };
    scrolling_frame_ut["setContentView"] = [](brls::ScrollingFrame& self, brls::View* v) { self.setContentView(v); };
    brls_ns["ScrollingFrame"]["create"] = []() { return brls::ScrollingFrame::create(); };

    // AppletFrame
    auto applet_frame_ut = brls_ns.new_usertype<brls::AppletFrame>("AppletFrame",
        sol::factories(
            []() { return new brls::AppletFrame(); }
        ),
        sol::base_classes, sol::bases<brls::Box, brls::View>()
    );
    applet_frame_ut["setTitle"] = &brls::AppletFrame::setTitle;
    applet_frame_ut["pushContentView"] = [](brls::AppletFrame& self, brls::View* v) { self.pushContentView(v); };
    applet_frame_ut["popContentView"] = [](brls::AppletFrame& self) { self.popContentView(); };
    applet_frame_ut["getContentView"] = [this](brls::AppletFrame& self) { return this->pushView(self.getContentView()); };
    applet_frame_ut["setHeaderVisibility"] = &brls::AppletFrame::setHeaderVisibility;
    applet_frame_ut["setFooterVisibility"] = &brls::AppletFrame::setFooterVisibility;
    brls_ns["AppletFrame"]["create"] = []() { return brls::AppletFrame::create(); };
}
