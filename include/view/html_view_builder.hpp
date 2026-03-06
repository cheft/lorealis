#pragma once

#include <borealis.hpp>
#include "view/html_parser.hpp"
#include "view/html_style.hpp"

namespace brls {

// Colour palette
static const NVGcolor HAN_TEXT        = nvgRGB(0x33, 0x33, 0x33);
static const NVGcolor HAN_BLACK       = nvgRGB(0x00, 0x00, 0x00);
static const NVGcolor HAN_EMERALD     = nvgRGB(0x1a, 0xbc, 0x9c);
static const NVGcolor HAN_QUOTE_TEXT  = nvgRGB(0x99, 0x99, 0x99);
static const NVGcolor HAN_HR_COLOR    = nvgRGB(0xcf, 0xcf, 0xcf);
static const NVGcolor HAN_BORDER_DDD  = nvgRGB(0xdd, 0xdd, 0xdd);
static const NVGcolor HAN_CODE_BG     = nvgRGBA(135, 131, 120, 38);
static const NVGcolor HAN_CODE_TEXT   = nvgRGB(0xEB, 0x57, 0x57);
static const NVGcolor HAN_STRONG_TEXT = nvgRGB(0x00, 0x00, 0x00);
static const NVGcolor HAN_TH_BG       = nvgRGB(0xf1, 0xf1, 0xf1);
static const NVGcolor HAN_TD_TEXT     = nvgRGB(0x66, 0x66, 0x66);
static const NVGcolor HAN_PRE_BG      = nvgRGB(0xf5, 0xf5, 0xf5);
static const NVGcolor HAN_DEL_TEXT    = nvgRGB(0x99, 0x99, 0x99);
static const NVGcolor HAN_COPY_BTN    = nvgRGB(0x88, 0x88, 0x88);
static const NVGcolor HAN_LINK_BLUE   = nvgRGB(0x1a, 0x73, 0xe8);
static const NVGcolor HAN_DARK_BG     = nvgRGB(0x1e, 0x1e, 0x2e);

static constexpr float BASE = 26.0f;

class HtmlViewBuilder {
public:
    static void buildHtmlViews(MiniNode* node, Box* parent, float& baseFontSize,
                               std::optional<NVGcolor>& currentTextColor,
                               const NVGcolor& defaultTextColor,
                               const NVGcolor& accentColor);
    
    static void renderInline(MiniNode* node, Box* target, float fontSize, NVGcolor color, bool strikethrough = false);
    static void renderInlineChildren(const std::vector<MiniNode*>& children, Box* target,
                                      float fontSize, NVGcolor color, bool strikethrough = false);
    
    static void applyStyle(View* view, const CssStyle& st);
    
private:
    static void buildTable(MiniNode* tableNode, Box* parent, float& baseFontSize,
                           std::optional<NVGcolor>& currentTextColor,
                           const NVGcolor& defaultTextColor,
                           const NVGcolor& accentColor);

    static Box* buildInlineRow(MiniNode* node, float fontSize, NVGcolor color, const std::string& align = "left");
};

} // namespace brls
