#pragma once

#include <borealis.hpp>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace brls {

// Minimal internal HTML node structure
struct MiniNode {
    std::string tag;
    std::string text;
    std::map<std::string, std::string> attributes;
    std::vector<MiniNode*> children;
    bool isText = false;

    ~MiniNode();
};

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

public:
    void applyStyle(View* view, const CssStyle& style);
    static void buildHtmlViews(HtmlRenderer* renderer, MiniNode* node, Box* parent, float& baseFontSize, std::optional<NVGcolor>& currentTextColor, const NVGcolor& defaultTextColor, const NVGcolor& accentColor);
};

} // namespace brls
