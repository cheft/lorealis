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
    // Typography
    std::optional<NVGcolor> color;
    std::optional<float>    fontSize;
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

public:
    CssStyle parseInlineStyle(const std::string& styleStr);
    void applyStyle(View* view, const CssStyle& style);
    static void buildHtmlViews(HtmlRenderer* renderer, MiniNode* node, Box* parent,
                               float& baseFontSize,
                               std::optional<NVGcolor>& currentTextColor,
                               const NVGcolor& defaultTextColor,
                               const NVGcolor& accentColor);
};

} // namespace brls
