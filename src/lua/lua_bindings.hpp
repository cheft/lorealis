#pragma once
#include <borealis.hpp>
#include <sol/sol.hpp>
#include <functional>

// Forward declaration for prepareForReuse callback (actual LuaRecyclerCell is in lua_recycler.cpp)
using PrepareForReuseCallback = std::function<void()>;

// Forward declaration of LuaRecyclerCell
class LuaRecyclerCell;

// Shim class to allow Lua to override draw()
class LuaImage : public brls::Image {
public:
    using DrawCallback = std::function<void(NVGcontext*, float, float, float, float, brls::Style, brls::FrameContext*)>;
    void setDrawCallback(DrawCallback cb) { drawCallback = cb; }
    
    void draw(NVGcontext* vg, float x, float y, float width, float height, brls::Style style, brls::FrameContext* ctx) override {
        if (drawCallback) {
            drawCallback(vg, x, y, width, height, style, ctx);
        } else {
            brls::Image::draw(vg, x, y, width, height, style, ctx);
        }
    }

    static brls::View* create() { return new LuaImage(); }

    float rotate_ = 0, skewX_ = 0, skewY_ = 0;
    float scaleX_ = 1, scaleY_ = 1;
    float fontScaleX_ = 1, fontScaleY_ = 1;

private:
    DrawCallback drawCallback;
};
