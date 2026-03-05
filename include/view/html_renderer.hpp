#pragma once

#include <borealis.hpp>
#include <string>
#include <vector>
#include <map>

namespace brls {

struct CssStyle {
    std::optional<NVGcolor> color;
    std::optional<float> fontSize;
    std::optional<float> marginTop;
    std::optional<float> marginBottom;
};

class HtmlRenderer : public Box {
public:
    HtmlRenderer();
    ~HtmlRenderer();

    static HtmlRenderer* create();

    void renderString(const std::string& html);
    void renderFile(const std::string& path);

    // Setters for styling
    void setBaseFontSize(float size) { baseFontSize = size; }
    void setTextColor(NVGcolor color) { customTextColor = color; }

private:
    float baseFontSize = 24.0f;
    std::optional<NVGcolor> customTextColor;
    
    NVGcolor getThemeColor(const std::string& key);
    CssStyle parseInlineStyle(const std::string& styleStr);
    void applyStyle(View* view, const CssStyle& style);
};

} // namespace brls
