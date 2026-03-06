#pragma once

#include <optional>
#include <string>
#include <nanovg.h>

namespace brls {

struct CssStyle {
    // Typography
    std::optional<NVGcolor> color;
    std::optional<float>    fontSize;
    std::optional<float>    lineHeight;
    std::optional<bool>     fontBold;
    std::optional<float>    opacity;

    // Spacing — margin
    std::optional<float>    marginTop;
    std::optional<float>    marginRight;
    std::optional<float>    marginBottom;
    std::optional<float>    marginLeft;

    // Spacing — padding
    std::optional<float>    paddingTop;
    std::optional<float>    paddingRight;
    std::optional<float>    paddingBottom;
    std::optional<float>    paddingLeft;

    // Box appearance
    std::optional<NVGcolor> backgroundColor;
    std::optional<float>    borderRadius;
    std::optional<float>    borderWidth;
    std::optional<NVGcolor> borderColor;

    // Text decoration / alignment
    std::optional<std::string> textAlign;          // "left" | "center" | "right"
    std::optional<bool>        textDecorationLine; // true = strikethrough

    // Dimension
    std::optional<float>    width;
    std::optional<float>    widthPercentage;
    std::optional<float>    height;
    std::optional<float>    heightPercentage;
    std::optional<bool>     overflowHidden;
};

class HtmlStyle {
public:
    static CssStyle parseInlineStyle(const std::string& css);
    static std::optional<NVGcolor> parseColor(const std::string& str);
    static float parseSize(const std::string& str, float base = 0.0f);
};

} // namespace brls
