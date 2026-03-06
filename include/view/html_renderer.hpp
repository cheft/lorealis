#pragma once

#include <borealis.hpp>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "view/html_parser.hpp"
#include "view/html_style.hpp"

namespace brls {

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

public:
    brls::CssStyle parseInlineStyle(const std::string& styleStr);
    void applyStyle(brls::View* view, const brls::CssStyle& style);
};

} // namespace brls
