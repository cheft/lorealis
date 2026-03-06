/*
 * html_renderer.cpp  —  HtmlRenderer
 *
 * This file serves as the wrapper for parsing and building HTML views.
 * The heavy lifting is done in html_parser.cpp, html_style.cpp, and
 * html_view_builder.cpp.
 */
#include "view/html_renderer.hpp"
#include "view/html_parser.hpp"
#include "view/html_view_builder.hpp"
#include "network/http_client.hpp"
#include <borealis/core/logger.hpp>
#include <fstream>
#include <sstream>

namespace brls {

// ============================================================
// HtmlRenderer lifecycle
// ============================================================
HtmlRenderer::HtmlRenderer()  { 
    setAxis(Axis::COLUMN); 
    setPadding(0); 
    setAlignItems(AlignItems::CENTER);
}
HtmlRenderer::~HtmlRenderer() {}
HtmlRenderer* HtmlRenderer::create() { return new HtmlRenderer(); }

void HtmlRenderer::renderFile(const std::string& path) {
    std::ifstream f(path);
    if (!f.is_open()) { Logger::error("HtmlRenderer: can't open {}", path); return; }
    std::stringstream buf; buf << f.rdbuf();
    renderString(buf.str());
}

// ============================================================
// parseInlineStyle (interface forwarder)
// ============================================================
CssStyle HtmlRenderer::parseInlineStyle(const std::string& css) {
    return HtmlStyle::parseInlineStyle(css);
}

// ============================================================
// applyStyle (interface forwarder)
// ============================================================
void HtmlRenderer::applyStyle(View* view, const CssStyle& st) {
    HtmlViewBuilder::applyStyle(view, st);
}

NVGcolor HtmlRenderer::getThemeColor(const std::string& key) {
    return Application::getTheme().getColor(key);
}

// ============================================================
// renderString  —  entry point
// ============================================================
void HtmlRenderer::renderString(const std::string& html) {
    clearViews();
    MiniNode* root = HtmlParser::parseHTML(html);
    NVGcolor def = HAN_TEXT;
    NVGcolor acc = HAN_EMERALD;
    float fs = baseFontSize;
    std::optional<NVGcolor> tc = customTextColor;
    
    HtmlViewBuilder::buildHtmlViews(root, this, fs, tc, def, acc);
    delete root;
}

} // namespace brls
