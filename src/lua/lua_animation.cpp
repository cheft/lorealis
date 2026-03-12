#include "lua_manager.hpp"
#include "lua_bindings.hpp"

void LuaManager::registerAnimationBindings(sol::table& brls_ns) {
     // Animations
    auto animatable_ut = brls_ns.new_usertype<brls::Animatable>("Animatable",
        sol::constructors<brls::Animatable(), brls::Animatable(float)>()
    );
    animatable_ut["getValue"] = &brls::Animatable::getValue;
    animatable_ut.set_function("reset", [](brls::Animatable& self, sol::optional<float> val) {
        if (val) self.reset(*val);
        else self.reset();
    });
    animatable_ut.set_function("addStep", [](brls::Animatable& self, float target, int duration, int easing) {
        self.addStep(target, duration, (brls::EasingFunction)easing);
    });
    animatable_ut["getProgress"] = &brls::Animatable::getProgress;
    animatable_ut.set_function("start", [](brls::Animatable& self) { self.start(); });
    animatable_ut.set_function("stop", [](brls::Animatable& self) { self.stop(); });
    animatable_ut.set_function("setTickCallback", [](brls::Animatable& self, sol::protected_function cb) {
        // Clear existing callback to prevent accumulation on repeated calls
        self.setTickCallback(nullptr);
        self.setTickCallback([cb]() {
            if (cb.valid()) {
                auto res = cb();
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua Animatable tick error: {}", err.what()); }
            }
        });
    });

    brls_ns["EasingFunction"] = lua.create_table_with(
        "linear", (int)brls::EasingFunction::linear,
        "quadraticIn", (int)brls::EasingFunction::quadraticIn,
        "quadraticOut", (int)brls::EasingFunction::quadraticOut,
        "quadraticInOut", (int)brls::EasingFunction::quadraticInOut,
        "cubicIn", (int)brls::EasingFunction::cubicIn,
        "cubicOut", (int)brls::EasingFunction::cubicOut,
        "cubicInOut", (int)brls::EasingFunction::cubicInOut,
        "quarticIn", (int)brls::EasingFunction::quarticIn,
        "quarticOut", (int)brls::EasingFunction::quarticOut,
        "quarticInOut", (int)brls::EasingFunction::quarticInOut,
        "quinticIn", (int)brls::EasingFunction::quinticIn,
        "quinticOut", (int)brls::EasingFunction::quinticOut,
        "quinticInOut", (int)brls::EasingFunction::quinticInOut,
        "sinusoidalIn", (int)brls::EasingFunction::sinusoidalIn,
        "sinusoidalOut", (int)brls::EasingFunction::sinusoidalOut,
        "sinusoidalInOut", (int)brls::EasingFunction::sinusoidalInOut,
        "exponentialIn", (int)brls::EasingFunction::exponentialIn,
        "exponentialOut", (int)brls::EasingFunction::exponentialOut,
        "exponentialInOut", (int)brls::EasingFunction::exponentialInOut,
        "circularIn", (int)brls::EasingFunction::circularIn,
        "circularOut", (int)brls::EasingFunction::circularOut,
        "circularInOut", (int)brls::EasingFunction::circularInOut,
        "bounceIn", (int)brls::EasingFunction::bounceIn,
        "bounceOut", (int)brls::EasingFunction::bounceOut,
        "bounceInOut", (int)brls::EasingFunction::bounceInOut,
        "elasticIn", (int)brls::EasingFunction::elasticIn,
        "elasticOut", (int)brls::EasingFunction::elasticOut,
        "elasticInOut", (int)brls::EasingFunction::elasticInOut,
        "backIn", (int)brls::EasingFunction::backIn,
        "backOut", (int)brls::EasingFunction::backOut,
        "backInOut", (int)brls::EasingFunction::backInOut
    );

    // LuaImage (subclass of Image)
    auto lua_image_ut = brls_ns.new_usertype<LuaImage>("LuaImage",
        sol::no_constructor,
        sol::base_classes, sol::bases<brls::Image, brls::View>()
    );
    lua_image_ut.set_function("setDrawCallback", [](LuaImage& self, sol::protected_function cb) {
        self.setDrawCallback([cb](NVGcontext* vg, float x, float y, float w, float h, brls::Style style, brls::FrameContext* ctx) {
            auto res = cb((void*)vg, x, y, w, h, style, ctx);
            if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in drawCallback: {}", err.what()); }
        });
    });
    // Workaround for sol2 typing NVGcontext* vs void* inside Lua
    lua_image_ut.set_function("drawBase", [](LuaImage& self, void* vg, float x, float y, float w, float h, brls::Style style, brls::FrameContext* ctx) {
        self.brls::Image::draw((NVGcontext*)vg, x, y, w, h, style, ctx);
    });
    lua_image_ut["rotate_"]     = &LuaImage::rotate_;
    lua_image_ut["skewX_"]      = &LuaImage::skewX_;
    lua_image_ut["skewY_"]      = &LuaImage::skewY_;
    lua_image_ut["scaleX_"]     = &LuaImage::scaleX_;
    lua_image_ut["scaleY_"]     = &LuaImage::scaleY_;
    lua_image_ut["fontScaleX_"] = &LuaImage::fontScaleX_;
    lua_image_ut["fontScaleY_"] = &LuaImage::fontScaleY_;
    
    // TransformBox aliases
    lua_image_ut.set_function("setRotate", [](LuaImage& self, float v) { self.rotate_ = v; });
    lua_image_ut.set_function("setSkewX", [](LuaImage& self, float v) { self.skewX_ = v; });
    lua_image_ut.set_function("setSkewY", [](LuaImage& self, float v) { self.skewY_ = v; });
    lua_image_ut.set_function("setScaleX", [](LuaImage& self, float v) { self.scaleX_ = v; });
    lua_image_ut.set_function("setScaleY", [](LuaImage& self, float v) { self.scaleY_ = v; });
    lua_image_ut.set_function("setFontScaleX", [](LuaImage& self, float v) { self.fontScaleX_ = v; });
    lua_image_ut.set_function("setFontScaleY", [](LuaImage& self, float v) { self.fontScaleY_ = v; });
    
    brls_ns["LuaImage"] = lua.create_table();
    brls_ns["LuaImage"]["new"] = []() { return new LuaImage(); };
}
