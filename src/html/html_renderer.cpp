/*
 * html_renderer.cpp  —  HtmlRenderer (extended inline-style support)
 *
 * Supports the full set of CSS properties used in the email test template:
 *   color, background-color, font-size, font-weight, opacity,
 *   margin / padding (shorthand + individual), border / border-radius,
 *   text-align, text-decoration.
 */
#include "view/html_renderer.hpp"
#include "network/http_client.hpp"
#include <borealis/core/logger.hpp>
#include <fstream>
#include <sstream>
#include <stack>
#include <set>
#include <algorithm>
#include "utils/image_utils.hpp"
#include <nanovg.h>
#include <borealis/core/touch/tap_gesture.hpp>

namespace brls {

// ============================================================
// Colour palette (han.css heritage + email-template colours)
// ============================================================
static const NVGcolor HAN_TEXT        = nvgRGB(0x33, 0x33, 0x33);
static const NVGcolor HAN_BLACK       = nvgRGB(0x00, 0x00, 0x00);
static const NVGcolor HAN_EMERALD     = nvgRGB(0x1a, 0xbc, 0x9c);
static const NVGcolor HAN_QUOTE_TEXT  = nvgRGB(0x99, 0x99, 0x99);
static const NVGcolor HAN_HR_COLOR    = nvgRGB(0xcf, 0xcf, 0xcf);
static const NVGcolor HAN_H1_BORDER   = nvgRGB(0xee, 0xee, 0xee);
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

// ============================================================
// MiniNode
// ============================================================
MiniNode::~MiniNode() { for (auto* c : children) delete c; }

// ============================================================
// HtmlRenderer lifecycle
// ============================================================
HtmlRenderer::HtmlRenderer()  { setAxis(Axis::COLUMN); setPadding(20); }
HtmlRenderer::~HtmlRenderer() {}
HtmlRenderer* HtmlRenderer::create() { return new HtmlRenderer(); }

void HtmlRenderer::renderFile(const std::string& path) {
    std::ifstream f(path);
    if (!f.is_open()) { Logger::error("HtmlRenderer: can't open {}", path); return; }
    std::stringstream buf; buf << f.rdbuf();
    renderString(buf.str());
}

// ============================================================
// String utilities
// ============================================================
static std::string strTrim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return {};
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

static std::string toLower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), ::tolower);
    return s;
}

static std::string unescapeHtml(const std::string& s) {
    std::string res; res.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '&') {
            if (s.compare(i, 4, "&lt;")   == 0) { res += '<'; i += 3; continue; }
            if (s.compare(i, 4, "&gt;")   == 0) { res += '>'; i += 3; continue; }
            if (s.compare(i, 5, "&amp;")  == 0) { res += '&'; i += 4; continue; }
            if (s.compare(i, 6, "&quot;") == 0) { res += '"'; i += 5; continue; }
            if (s.compare(i, 6, "&nbsp;") == 0) { res += ' '; i += 5; continue; }
            if (s.compare(i, 6, "&#169;") == 0) { res += "©"; i += 5; continue; }
        }
        res += s[i];
    }
    return res;
}

static std::string collectText(MiniNode* n) {
    if (n->isText) return n->text;
    std::string r; for (auto* c : n->children) r += collectText(c); return r;
}

static bool isInlineTag(const std::string& t) {
    static const std::set<std::string> S = {
        "strong","b","i","em","span","a","u","code","font",
        "small","big","del","s","ins","mark","sup","sub","br"
    };
    return S.count(t) > 0;
}

static bool isInlineNode(MiniNode* n) {
    return n->isText || isInlineTag(n->tag);
}

// ============================================================
// HTML Parser
// ============================================================
static MiniNode* parseHTML(const std::string& html) {
    MiniNode* root = new MiniNode(); root->tag = "root";
    std::stack<MiniNode*> stk; stk.push(root);

    auto topNode = [&]() -> MiniNode* { return stk.top(); };

    size_t i = 0, n = html.size();
    while (i < n) {
        if (html[i] != '<') {
            size_t end = html.find('<', i);
            std::string raw = html.substr(i, end == std::string::npos ? std::string::npos : end - i);
            i = (end == std::string::npos) ? n : end;

            bool inPre = false;
            std::stack<MiniNode*> tempStack = stk;
            while (!tempStack.empty()) {
                if (tempStack.top()->tag == "pre") { inPre = true; break; }
                tempStack.pop();
            }

            if (inPre) {
                MiniNode* tn = new MiniNode(); tn->isText = true; tn->text = unescapeHtml(raw);
                topNode()->children.push_back(tn);
            } else {
                std::string norm;
                bool lastWasSpace = false;
                for (char c : raw) {
                    if (isspace((unsigned char)c)) {
                        if (!lastWasSpace) { norm += ' '; lastWasSpace = true; }
                    } else { norm += c; lastWasSpace = false; }
                }
                if (norm == " " && topNode()->children.empty()) continue;
                if (norm.empty()) continue;
                MiniNode* tn = new MiniNode(); tn->isText = true; tn->text = unescapeHtml(norm);
                topNode()->children.push_back(tn);
            }
            continue;
        }

        size_t end = html.find('>', i);
        if (end == std::string::npos) break;
        std::string tc = html.substr(i + 1, end - i - 1);
        i = end + 1;
        if (tc.empty()) continue;
        if (tc.substr(0, 3) == "!--") { i = html.find("-->", i - tc.size() - 2); if (i == std::string::npos) i = n; else i += 3; continue; }
        if (tc[0] == '/') { if (stk.size() > 1) stk.pop(); continue; }

        bool sc = (!tc.empty() && tc.back() == '/');
        if (sc) tc.pop_back();
        if (!tc.empty() && tc.back() == ' ') tc.pop_back();

        std::istringstream iss(tc);
        std::string tagName; iss >> tagName;
        std::transform(tagName.begin(), tagName.end(), tagName.begin(), ::tolower);

        MiniNode* nd = new MiniNode(); nd->tag = tagName;

        // Parse attributes
        std::string rest; std::getline(iss, rest);
        size_t p = 0;
        while (p < rest.size()) {
            while (p < rest.size() && isspace((unsigned char)rest[p])) p++;
            if (p >= rest.size()) break;
            size_t eq = rest.find('=', p);
            if (eq == std::string::npos) break;
            std::string key = rest.substr(p, eq - p);
            { size_t a = key.find_first_not_of(" \t");
              size_t b = key.find_last_not_of(" \t");
              key = (a == std::string::npos) ? "" : key.substr(a, b - a + 1); }
            p = eq + 1;
            if (p >= rest.size()) break;
            char q = rest[p];
            if (q != '"' && q != '\'') { p++; continue; }
            p++;
            size_t ve = rest.find(q, p);
            if (ve == std::string::npos) break;
            nd->attributes[key] = rest.substr(p, ve - p);
            p = ve + 1;
        }

        topNode()->children.push_back(nd);
        bool voidEl = (tagName=="br"||tagName=="img"||tagName=="hr"||
                       tagName=="input"||tagName=="meta"||tagName=="link");
        if (!sc && !voidEl) stk.push(nd);
    }
    return root;
}

// ============================================================
// parseColor — supports #rrggbb, #rgb, rgba(), named colours
// ============================================================
static std::optional<NVGcolor> parseColor(const std::string& raw) {
    std::string s = strTrim(raw);
    if (s.empty()) return std::nullopt;

    // #rrggbb
    if (s.size() == 7 && s[0] == '#') {
        int r, g, b;
        if (sscanf(s.c_str(), "#%02x%02x%02x", &r, &g, &b) == 3)
            return nvgRGB(r, g, b);
    }
    // #rgb  →  #rrggbb
    if (s.size() == 4 && s[0] == '#') {
        int r = 0, g = 0, b = 0;
        if (sscanf(s.c_str(), "#%1x%1x%1x", &r, &g, &b) == 3)
            return nvgRGB(r * 17, g * 17, b * 17);
    }
    // rgba(r,g,b,a)
    if (s.size() > 5 && s.substr(0, 5) == "rgba(") {
        int r = 0, g = 0, b = 0; float a = 1.0f;
        if (sscanf(s.c_str(), "rgba(%d,%d,%d,%f)", &r, &g, &b, &a) >= 3)
            return nvgRGBAf(r/255.0f, g/255.0f, b/255.0f, a);
    }
    // rgb(r,g,b)
    if (s.size() > 4 && s.substr(0, 4) == "rgb(") {
        int r = 0, g = 0, b = 0;
        if (sscanf(s.c_str(), "rgb(%d,%d,%d)", &r, &g, &b) == 3)
            return nvgRGB(r, g, b);
    }
    // named
    if (s=="red")         return nvgRGB(255,0,0);
    if (s=="green")       return nvgRGB(0,128,0);
    if (s=="blue")        return nvgRGB(0,0,255);
    if (s=="white")       return nvgRGB(255,255,255);
    if (s=="black")       return nvgRGB(0,0,0);
    if (s=="gray"||s=="grey") return nvgRGB(128,128,128);
    if (s=="transparent") return nvgRGBA(0,0,0,0);
    return std::nullopt;
}

// Helper: parse a CSS length value (e.g. "12px", "1.5em") → float dp
static float parsePx(const std::string& v) {
    try { return std::stof(v); } catch (...) { return 0.f; }
}

// Helper: parse up-to-4-value shorthand into [top, right, bottom, left]
static void parseSpacing(const std::string& v,
                          float& t, float& r, float& b, float& l) {
    std::istringstream ss(v);
    std::vector<float> vals;
    std::string tok;
    while (ss >> tok) vals.push_back(parsePx(tok));
    if (vals.size() == 1) { t = r = b = l = vals[0]; }
    else if (vals.size() == 2) { t = b = vals[0]; r = l = vals[1]; }
    else if (vals.size() == 3) { t = vals[0]; r = l = vals[1]; b = vals[2]; }
    else if (vals.size() >= 4) { t = vals[0]; r = vals[1]; b = vals[2]; l = vals[3]; }
}

// ============================================================
// parseInlineStyle
// ============================================================
CssStyle HtmlRenderer::parseInlineStyle(const std::string& css) {
    CssStyle st;
    std::istringstream ss(css);
    std::string seg;
    while (std::getline(ss, seg, ';')) {
        size_t c = seg.find(':');
        if (c == std::string::npos) continue;
        std::string k = toLower(strTrim(seg.substr(0, c)));
        std::string v = strTrim(seg.substr(c + 1));
        if (k.empty() || v.empty()) continue;

        if (k == "color") {
            st.color = parseColor(v);
        }
        else if (k == "background-color" || k == "background") {
            st.backgroundColor = parseColor(v);
        }
        else if (k == "font-size") {
            try { st.fontSize = std::stof(v); } catch (...) {}
        }
        else if (k == "font-weight") {
            st.fontBold = (v == "bold" || v == "600" || v == "700" || v == "800" || v == "900");
        }
        else if (k == "opacity") {
            try { st.opacity = std::stof(v); } catch (...) {}
        }
        else if (k == "border-radius") {
            try { st.borderRadius = std::stof(v); } catch (...) {}
        }
        else if (k == "text-align") {
            st.textAlign = toLower(v);
        }
        else if (k == "text-decoration") {
            st.textDecorationLine = (toLower(v).find("line-through") != std::string::npos);
        }
        else if (k == "margin") {
            float t=0,r=0,b=0,l=0;
            parseSpacing(v,t,r,b,l);
            st.marginTop = t; st.marginRight = r; st.marginBottom = b; st.marginLeft = l;
        }
        else if (k == "margin-top")    { try { st.marginTop    = std::stof(v); } catch (...) {} }
        else if (k == "margin-bottom") { try { st.marginBottom = std::stof(v); } catch (...) {} }
        else if (k == "margin-left")   { try { st.marginLeft   = std::stof(v); } catch (...) {} }
        else if (k == "margin-right")  { try { st.marginRight  = std::stof(v); } catch (...) {} }
        else if (k == "padding") {
            float t=0,r=0,b=0,l=0;
            parseSpacing(v,t,r,b,l);
            st.paddingTop = t; st.paddingRight = r; st.paddingBottom = b; st.paddingLeft = l;
        }
        else if (k == "padding-top")    { try { st.paddingTop    = std::stof(v); } catch (...) {} }
        else if (k == "padding-bottom") { try { st.paddingBottom = std::stof(v); } catch (...) {} }
        else if (k == "padding-left")   { try { st.paddingLeft   = std::stof(v); } catch (...) {} }
        else if (k == "padding-right")  { try { st.paddingRight  = std::stof(v); } catch (...) {} }
        else if (k == "border" || k == "border-bottom" || k == "border-top") {
            // e.g. "1px solid #dadce0"
            auto col = parseColor(v.substr(v.rfind(' ') + 1));
            if (col) st.borderColor = col;
            try { st.borderWidth = std::stof(v); } catch (...) { st.borderWidth = 1.f; }
        }
    }
    return st;
}

NVGcolor HtmlRenderer::getThemeColor(const std::string& key) {
    return Application::getTheme().getColor(key);
}

// ============================================================
// applyStyle — apply CssStyle to a View / Box
// ============================================================
void HtmlRenderer::applyStyle(View* view, const CssStyle& st) {
    // View-level: margins (all views support these)
    if (st.marginTop)    view->setMarginTop(*st.marginTop);
    if (st.marginBottom) view->setMarginBottom(*st.marginBottom);
    if (st.marginLeft)   view->setMarginLeft(*st.marginLeft);
    if (st.marginRight)  view->setMarginRight(*st.marginRight);

    // Box-level APIs — requires Box*
    if (auto* box = dynamic_cast<Box*>(view)) {
        if (st.paddingTop)    box->setPaddingTop(*st.paddingTop);
        if (st.paddingBottom) box->setPaddingBottom(*st.paddingBottom);
        if (st.paddingLeft)   box->setPaddingLeft(*st.paddingLeft);
        if (st.paddingRight)  box->setPaddingRight(*st.paddingRight);
        if (st.backgroundColor) box->setBackgroundColor(*st.backgroundColor);
        if (st.borderRadius)    box->setCornerRadius(*st.borderRadius);
        if (st.opacity)         box->setAlpha(*st.opacity);
        if (st.borderWidth && st.borderColor) {
            box->setBorderThickness(*st.borderWidth);
            box->setBorderColor(*st.borderColor);
        }
    }

    // Label-level
    if (auto* lbl = dynamic_cast<Label*>(view)) {
        if (st.color)    lbl->setTextColor(*st.color);
        if (st.fontSize) lbl->setFontSize(*st.fontSize);
    }
}

// ============================================================
// Shared widget factories
// ============================================================
static Label* makeLabel(const std::string& text, float fontSize, NVGcolor color) {
    Label* l = new Label();
    l->setText(text);
    l->setFontSize(fontSize);
    l->setTextColor(color);
    return l;
}

static Box* makeHR() {
    Box* hr = new Box(Axis::ROW);
    hr->setHeight(1.5f);
    hr->setBackgroundColor(HAN_HR_COLOR);
    hr->setMarginTop(18); hr->setMarginBottom(18);
    return hr;
}

static void attachH1Border(Box* container) {
    Box* l1 = new Box(Axis::ROW); l1->setHeight(1.5f); l1->setBackgroundColor(HAN_H1_BORDER); l1->setMarginTop(14);
    Box* gap = new Box(Axis::ROW); gap->setHeight(2.0f);
    Box* l2 = new Box(Axis::ROW); l2->setHeight(1.5f); l2->setBackgroundColor(HAN_H1_BORDER);
    container->addView(l1); container->addView(gap); container->addView(l2);
}

// Apply justification from textAlign string to a ROW box
static void applyTextAlign(Box* row, const std::string& align) {
    if (align == "center") row->setJustifyContent(JustifyContent::CENTER);
    else if (align == "right") row->setJustifyContent(JustifyContent::FLEX_END);
    else row->setJustifyContent(JustifyContent::FLEX_START);
}

// ============================================================
// Inline renderer
// ============================================================
static void renderInline(MiniNode* node, Box* target, float fontSize, NVGcolor color, bool strikethrough = false);

static void renderInlineChildren(const std::vector<MiniNode*>& children, Box* target,
                                  float fontSize, NVGcolor color, bool strikethrough = false) {
    for (auto* c : children) renderInline(c, target, fontSize, color, strikethrough);
}

static void renderInline(MiniNode* node, Box* target, float fontSize, NVGcolor color, bool strikethrough) {
    if (node->isText) {
        if (node->text.empty()) return;
        std::string txt = node->text;
        bool hasLeadingSpace  = !txt.empty() && txt.front() == ' ';
        bool hasTrailingSpace = !txt.empty() && txt.back()  == ' ';
        size_t start = txt.find_first_not_of(' ');
        size_t end   = txt.find_last_not_of(' ');
        if (start == std::string::npos) {
            Box* spacer = new Box(Axis::ROW); spacer->setWidth(fontSize * 0.3f);
            target->addView(spacer); return;
        }
        std::string trimmed = txt.substr(start, end - start + 1);
        Label* l = makeLabel(trimmed, fontSize, strikethrough ? HAN_DEL_TEXT : color);
        if (strikethrough) l->setLineBottom(1); // visual approximation
        if (hasLeadingSpace)  l->setMarginLeft(fontSize * 0.3f);
        if (hasTrailingSpace) l->setMarginRight(fontSize * 0.3f);
        target->addView(l);
        return;
    }

    const std::string& t = node->tag;

    if (t == "strong" || t == "b") {
        renderInlineChildren(node->children, target, fontSize, HAN_STRONG_TEXT, strikethrough);
    }
    else if (t == "em" || t == "i") {
        renderInlineChildren(node->children, target, fontSize, nvgRGB(0x55,0x55,0x55), strikethrough);
    }
    else if (t == "del" || t == "s") {
        renderInlineChildren(node->children, target, fontSize, HAN_DEL_TEXT, true);
    }
    else if (t == "span") {
        // Check for inline style on span
        std::string styleStr = node->attributes.count("style") ? node->attributes.at("style") : "";
        NVGcolor spanColor = color;
        bool spanStrike = strikethrough;
        if (!styleStr.empty()) {
            // Quick parse just for color / text-decoration
            std::istringstream ss(styleStr); std::string seg;
            while (std::getline(ss, seg, ';')) {
                size_t c = seg.find(':'); if (c == std::string::npos) continue;
                std::string k = strTrim(toLower(seg.substr(0,c)));
                std::string v = strTrim(seg.substr(c+1));
                if (k == "color") { auto col = parseColor(v); if (col) spanColor = *col; }
                if (k == "text-decoration" && v.find("line-through") != std::string::npos) spanStrike = true;
            }
        }
        renderInlineChildren(node->children, target, fontSize, spanColor, spanStrike);
    }
    else if (t == "code") {
        // Check for per-code colour (used in monospace div blocks)
        NVGcolor codeColor = HAN_CODE_TEXT;
        if (node->attributes.count("style")) {
            std::istringstream ss(node->attributes.at("style")); std::string seg;
            while (std::getline(ss, seg, ';')) {
                size_t c = seg.find(':'); if (c == std::string::npos) continue;
                std::string k = strTrim(toLower(seg.substr(0,c)));
                std::string v = strTrim(seg.substr(c+1));
                if (k == "color") { auto col = parseColor(v); if (col) codeColor = *col; }
            }
        }
        Box* cBox = new Box(Axis::ROW);
        cBox->setBackgroundColor(HAN_CODE_BG);
        cBox->setCornerRadius(4);
        cBox->setPadding(2, 8, 2, 8);
        cBox->addView(makeLabel(collectText(node), fontSize * 0.85f, codeColor));
        target->addView(cBox);
    }
    else if (t == "a") {
        std::string href = node->attributes.count("href") ? node->attributes.at("href") : "";
        // Check if this is a styled button (has background-color in style)
        std::string styleStr = node->attributes.count("style") ? node->attributes.at("style") : "";
        bool isButton = styleStr.find("background-color") != std::string::npos &&
                        styleStr.find("#ffffff") == std::string::npos &&
                        styleStr.find("white") == std::string::npos;
        NVGcolor linkColor = HAN_LINK_BLUE;
        if (!styleStr.empty()) {
            std::istringstream ss(styleStr); std::string seg;
            while (std::getline(ss, seg, ';')) {
                size_t c = seg.find(':'); if (c == std::string::npos) continue;
                std::string k = strTrim(toLower(seg.substr(0,c)));
                std::string v = strTrim(seg.substr(c+1));
                if (k == "color") { auto col = parseColor(v); if (col) linkColor = *col; }
            }
        }
        std::string txt = collectText(node);
        Label* lbl = makeLabel(txt, fontSize, linkColor);
        lbl->setLineBottom(1); lbl->setLineColor(linkColor);
        if (!href.empty()) {
            lbl->setFocusable(true);
            lbl->registerClickAction([href](View*) { Application::getPlatform()->openBrowser(href); return true; });
            lbl->addGestureRecognizer(new TapGestureRecognizer([href](TapGestureStatus s, Sound*) {
                if (s.state == GestureState::END) Application::getPlatform()->openBrowser(href);
            }));
        }
        target->addView(lbl);
    }
    else if (t == "br") {
        Box* br = new Box(Axis::ROW); br->setHeight(fontSize * 0.5f);
        target->addView(br);
    }
    else if (t == "img") {
        std::string src = node->attributes.count("src") ? node->attributes.at("src") : "";
        if (!src.empty()) {
            Image* img = new Image();
            img->setScalingType(ImageScalingType::FIT);
            img->setAspectRatio(16.0f / 9.0f);
            img->setCornerRadius(6);
            img->setMarginTop(12); img->setMarginBottom(12);
            Box* imgContainer = new Box(Axis::ROW);
            imgContainer->setJustifyContent(JustifyContent::CENTER);
            imgContainer->setWidthPercentage(100);
            img->setWidthPercentage(80);
            imgContainer->addView(img);
            target->addView(imgContainer);
            if (src.rfind("http", 0) == 0) {
                img->setImageAsync([src](std::function<void(const std::string&, size_t)> cb) {
                    SimpleHTTPClient::downloadImage(src, [cb](bool ok, const std::string& d) { if (ok) cb(d, d.size()); });
                });
            } else { img->setImageFromFile(src); }
        }
    }
    else {
        renderInlineChildren(node->children, target, fontSize, color, strikethrough);
    }
}

static Box* buildInlineRow(MiniNode* node, float fontSize, NVGcolor color,
                            const std::string& align = "left") {
    Box* row = new Box(Axis::ROW);
    row->setFlexWrap(true);
    row->setRowGap(10);
    row->setColumnGap(0);
    row->setAlignItems(AlignItems::FLEX_START);
    applyTextAlign(row, align);
    renderInlineChildren(node->children, row, fontSize, color);
    return row;
}

// ============================================================
// Table builder — now with per-row bg and per-cell text-align
// ============================================================
static void buildTable(HtmlRenderer* renderer, MiniNode* tableNode, Box* parent) {
    Box* tBox = new Box(Axis::COLUMN);
    tBox->setMarginBottom(22);
    tBox->setBorderThickness(1);
    tBox->setBorderColor(HAN_BORDER_DDD);

    std::vector<std::pair<bool, MiniNode*>> rows;
    std::function<void(MiniNode*, bool)> collect = [&](MiniNode* n, bool hdr) {
        for (auto* c : n->children) {
            if (c->tag == "tr") rows.push_back({hdr, c});
            else if (c->tag == "thead") collect(c, true);
            else if (c->tag == "tbody" || c->tag == "tfoot") collect(c, false);
        }
    };
    collect(tableNode, false);
    for (auto* c : tableNode->children) if (c->tag == "tr") rows.push_back({false, c});

    for (auto& [hdr, row] : rows) {
        // Row background from inline style
        CssStyle rowSt = renderer->parseInlineStyle(
            row->attributes.count("style") ? row->attributes.at("style") : "");

        Box* rowBox = new Box(Axis::ROW);

        int cols = 0;
        for (auto* c : row->children) if (c->tag == "td" || c->tag == "th") cols++;
        if (cols == 0) cols = 1;

        for (auto* cell : row->children) {
            if (cell->tag != "td" && cell->tag != "th") continue;
            bool isHdr = (cell->tag == "th") || hdr;

            CssStyle cellSt = renderer->parseInlineStyle(
                cell->attributes.count("style") ? cell->attributes.at("style") : "");

            Box* cellBox = new Box(Axis::COLUMN);
            cellBox->setGrow(1.0f);
            cellBox->setWidthPercentage(100.0f / cols);
            cellBox->setPadding(8, 16, 8, 16);
            cellBox->setBorderThickness(1);
            cellBox->setBorderColor(HAN_BORDER_DDD);
            cellBox->setMarginTop(0); cellBox->setMarginBottom(0);
            cellBox->setMarginLeft(0); cellBox->setMarginRight(0);

            // Background: cell style > row style > header default
            if (cellSt.backgroundColor) cellBox->setBackgroundColor(*cellSt.backgroundColor);
            else if (rowSt.backgroundColor) cellBox->setBackgroundColor(*rowSt.backgroundColor);
            else if (isHdr) cellBox->setBackgroundColor(HAN_TH_BG);

            // Border override from cell style
            if (cellSt.borderWidth && cellSt.borderColor) {
                cellBox->setBorderThickness(*cellSt.borderWidth);
                cellBox->setBorderColor(*cellSt.borderColor);
            }

            NVGcolor cellTextColor = cellSt.color ? *cellSt.color : (isHdr ? HAN_BLACK : HAN_TD_TEXT);
            std::string align = cellSt.textAlign ? *cellSt.textAlign : "left";

            Box* content = buildInlineRow(cell, BASE * 0.85f, cellTextColor, align);
            cellBox->addView(content);
            rowBox->addView(cellBox);
        }
        tBox->addView(rowBox);
    }
    parent->addView(tBox);
}

// ============================================================
// buildHtmlViews  —  recursive block-level builder
// ============================================================
void HtmlRenderer::buildHtmlViews(HtmlRenderer* renderer, MiniNode* node, Box* parent,
                                   float& baseFontSize,
                                   std::optional<NVGcolor>& currentTextColor,
                                   const NVGcolor& defaultTextColor,
                                   const NVGcolor& accentColor)
{
    if (node->isText) {
        NVGcolor col = currentTextColor ? *currentTextColor : defaultTextColor;
        parent->addView(makeLabel(node->text, baseFontSize, col));
        return;
    }

    const std::string& tag = node->tag;
    float       oldSize  = baseFontSize;
    auto        oldColor = currentTextColor;
    Box*        cont     = parent;
    bool        skip     = false;

    NVGcolor textCol = currentTextColor ? *currentTextColor : defaultTextColor;

    CssStyle ist = renderer->parseInlineStyle(
        node->attributes.count("style") ? node->attributes.at("style") : "");

    // Pull colour/size from inline style early for headings / p
    NVGcolor hColor = ist.color ? *ist.color : HAN_BLACK;
    std::string hAlign = ist.textAlign ? *ist.textAlign : "left";

    // ── Headings ──────────────────────────────────────────────────────
    auto makeHeading = [&](float scale, bool doubleBottom) {
        Box* hb = new Box(Axis::COLUMN);
        hb->setMarginTop(ist.marginTop ? *ist.marginTop : (scale >= 2.0f ? 32 : 18));
        hb->setMarginBottom(ist.marginBottom ? *ist.marginBottom : 10);
        Box* row = buildInlineRow(node, BASE * scale, hColor, hAlign);
        hb->addView(row);
        if (doubleBottom) attachH1Border(hb);
        parent->addView(hb);
        skip = true;
    };

    if      (tag == "h1") makeHeading(2.4f, true);
    else if (tag == "h2") makeHeading(1.8f, false);
    else if (tag == "h3") makeHeading(1.6f, false);
    else if (tag == "h4") makeHeading(1.4f, false);
    else if (tag == "h5" || tag == "h6") makeHeading(1.2f, false);

    // ── Paragraph ─────────────────────────────────────────────────────
    else if (tag == "p") {
        NVGcolor pCol = ist.color ? *ist.color : textCol;
        Box* pb = buildInlineRow(node, ist.fontSize ? *ist.fontSize : BASE, pCol, hAlign);
        pb->setMarginBottom(ist.marginBottom ? *ist.marginBottom : 22);
        if (ist.marginTop) pb->setMarginTop(*ist.marginTop);
        parent->addView(pb);
        skip = true;
    }

    // ── Blockquote ────────────────────────────────────────────────────
    else if (tag == "blockquote") {
        Box* qb = new Box(Axis::COLUMN);
        qb->setLineLeft(3); qb->setLineColor(HAN_EMERALD);
        qb->setPaddingLeft(20); qb->setPaddingTop(6); qb->setPaddingBottom(6);
        qb->setMarginTop(16); qb->setMarginBottom(22);
        qb->setMarginLeft(28); qb->setMarginRight(40);
        parent->addView(qb); cont = qb;
        currentTextColor = HAN_QUOTE_TEXT;
        for (auto* child : node->children)
            buildHtmlViews(renderer, child, cont, baseFontSize, currentTextColor, defaultTextColor, accentColor);
        skip = true;
    }

    // ── Lists ─────────────────────────────────────────────────────────
    else if (tag == "ul" || tag == "ol") {
        Box* lb = new Box(Axis::COLUMN);
        lb->setPaddingLeft(ist.paddingLeft ? *ist.paddingLeft : 24);
        lb->setMarginBottom(ist.marginBottom ? *ist.marginBottom : 22);
        if (ist.marginTop) lb->setMarginTop(*ist.marginTop);
        int counter = 1;
        bool ordered = (tag == "ol");

        for (auto* liNode : node->children) {
            if (liNode->tag != "li") continue;
            bool hasContent = false;
            for (auto* c : liNode->children) if (isInlineNode(c)) { hasContent = true; break; }
            if (liNode->children.empty()) hasContent = true;

            Box* row = new Box(Axis::ROW);
            row->setAlignItems(AlignItems::FLEX_START);
            row->setMarginBottom(6);

            if (hasContent) {
                Label* marker = makeLabel(ordered ? (std::to_string(counter++) + ". ") : "• ", BASE, textCol);
                row->addView(marker);
            }

            Box* rhs = new Box(Axis::COLUMN); rhs->setGrow(1.0f);
            Box* inlineRow = nullptr;
            for (auto* liChild : liNode->children) {
                if (liChild->tag == "ul" || liChild->tag == "ol") {
                    inlineRow = nullptr;
                    buildHtmlViews(renderer, liChild, rhs, baseFontSize, currentTextColor, defaultTextColor, accentColor);
                } else if (isInlineNode(liChild)) {
                    if (!inlineRow) {
                        inlineRow = new Box(Axis::ROW);
                        inlineRow->setFlexWrap(true); inlineRow->setRowGap(10);
                        inlineRow->setAlignItems(AlignItems::FLEX_START);
                        rhs->addView(inlineRow);
                    }
                    renderInline(liChild, inlineRow, BASE, textCol);
                } else {
                    inlineRow = nullptr;
                    buildHtmlViews(renderer, liChild, rhs, baseFontSize, currentTextColor, defaultTextColor, accentColor);
                }
            }
            row->addView(rhs);
            lb->addView(row);
        }
        parent->addView(lb);
        skip = true;
    }

    // ── Table ─────────────────────────────────────────────────────────
    else if (tag == "table") {
        buildTable(renderer, node, parent);
        skip = true;
    }

    // ── Pre / Code Block ──────────────────────────────────────────────
    else if (tag == "pre") {
        std::string lang;
        std::string codeText;
        for (auto* c : node->children) {
            if (c->tag == "code") {
                lang = c->attributes.count("class") ? c->attributes.at("class") : "";
                if (lang.substr(0, 5) == "lang-") lang = lang.substr(5);
                codeText = collectText(c);
            } else { codeText += collectText(c); }
        }
        if (codeText.empty()) codeText = collectText(node);

        Box* preOuter = new Box(Axis::COLUMN);
        preOuter->setMarginBottom(22);
        preOuter->setBorderThickness(1); preOuter->setBorderColor(HAN_BORDER_DDD);
        preOuter->setCornerRadius(4);

        Box* titleBar = new Box(Axis::ROW);
        titleBar->setBackgroundColor(nvgRGB(0xe8,0xe8,0xe8));
        titleBar->setPadding(6,12,6,12);
        titleBar->setAlignItems(AlignItems::CENTER);
        {
            Label* langLbl = makeLabel(lang.empty() ? "code" : lang, BASE*0.75f, HAN_COPY_BTN);
            langLbl->setGrow(1.0f); titleBar->addView(langLbl);
            Label* copyBtn = makeLabel("[ Copy ]", BASE*0.72f, HAN_COPY_BTN);
            copyBtn->setFocusable(true);
            const std::string captured = codeText;
            copyBtn->registerClickAction([captured](View*) {
                Application::getPlatform()->pasteToClipboard(captured);
                Application::notify("Copied to clipboard"); return true;
            });
            copyBtn->addGestureRecognizer(new TapGestureRecognizer([captured](TapGestureStatus s, Sound*) {
                if (s.state == GestureState::END) {
                    Application::getPlatform()->pasteToClipboard(captured);
                    Application::notify("Copied to clipboard");
                }
            }));
            titleBar->addView(copyBtn);
        }
        preOuter->addView(titleBar);

        Box* codeBox = new Box(Axis::COLUMN);
        codeBox->setBackgroundColor(HAN_PRE_BG); codeBox->setPadding(14);
        codeBox->addView(makeLabel(codeText, BASE*0.82f, HAN_TEXT));
        preOuter->addView(codeBox);
        parent->addView(preOuter);
        skip = true;
    }

    // ── Inline code block ──────────────────────────────────────────────
    else if (tag == "code") {
        NVGcolor codeColor = HAN_CODE_TEXT;
        if (ist.color) codeColor = *ist.color;
        Box* cb = new Box(Axis::ROW);
        cb->setBackgroundColor(HAN_CODE_BG); cb->setCornerRadius(4); cb->setPadding(2,8,2,8);
        cb->addView(makeLabel(collectText(node), BASE*0.85f, codeColor));
        parent->addView(cb);
        skip = true;
    }

    // ── HR ────────────────────────────────────────────────────────────
    else if (tag == "hr") { parent->addView(makeHR()); skip = true; }

    // ── BR ────────────────────────────────────────────────────────────
    else if (tag == "br") {
        Box* spacer = new Box(Axis::ROW); spacer->setHeight(BASE*0.5f);
        parent->addView(spacer); skip = true;
    }

    // ── Anchor block-level — may be a styled button ───────────────────
    else if (tag == "a") {
        std::string href = node->attributes.count("href") ? node->attributes.at("href") : "";
        bool isButton = ist.backgroundColor.has_value();

        if (isButton) {
            // Render as a styled clickable Box
            Box* btnBox = new Box(Axis::ROW);
            btnBox->setJustifyContent(JustifyContent::CENTER);
            btnBox->setAlignItems(AlignItems::CENTER);
            if (ist.backgroundColor) btnBox->setBackgroundColor(*ist.backgroundColor);
            if (ist.borderRadius)     btnBox->setCornerRadius(*ist.borderRadius);
            if (ist.paddingTop)    btnBox->setPaddingTop(*ist.paddingTop);
            if (ist.paddingBottom) btnBox->setPaddingBottom(*ist.paddingBottom);
            if (ist.paddingLeft)   btnBox->setPaddingLeft(*ist.paddingLeft);
            if (ist.paddingRight)  btnBox->setPaddingRight(*ist.paddingRight);
            if (ist.marginLeft)    btnBox->setMarginLeft(*ist.marginLeft);
            if (ist.marginRight)   btnBox->setMarginRight(*ist.marginRight);
            if (ist.borderWidth && ist.borderColor) {
                btnBox->setBorderThickness(*ist.borderWidth);
                btnBox->setBorderColor(*ist.borderColor);
            }
            NVGcolor lblColor = ist.color ? *ist.color : nvgRGB(255,255,255);
            float lblSize = ist.fontSize ? *ist.fontSize : BASE;
            Label* lbl = makeLabel(collectText(node), lblSize, lblColor);
            btnBox->addView(lbl);
            if (!href.empty()) {
                btnBox->setFocusable(true);
                btnBox->registerClickAction([href](View*) { Application::getPlatform()->openBrowser(href); return true; });
                btnBox->addGestureRecognizer(new TapGestureRecognizer([href](TapGestureStatus s, Sound*) {
                    if (s.state == GestureState::END) Application::getPlatform()->openBrowser(href);
                }));
            }
            parent->addView(btnBox);
        } else {
            Label* lbl = makeLabel(collectText(node), baseFontSize, HAN_LINK_BLUE);
            lbl->setLineBottom(1); lbl->setLineColor(HAN_LINK_BLUE);
            if (ist.color) lbl->setTextColor(*ist.color);
            if (!href.empty()) {
                lbl->setFocusable(true);
                lbl->registerClickAction([href](View*) { Application::getPlatform()->openBrowser(href); return true; });
                lbl->addGestureRecognizer(new TapGestureRecognizer([href](TapGestureStatus s, Sound*) {
                    if (s.state == GestureState::END) Application::getPlatform()->openBrowser(href);
                }));
            }
            parent->addView(lbl);
        }
        skip = true;
    }

    // ── Image ─────────────────────────────────────────────────────────
    else if (tag == "img") {
        std::string src = node->attributes.count("src") ? node->attributes.at("src") : "";
        if (!src.empty()) {
            Image* img = new Image();
            img->setScalingType(ImageScalingType::FIT);
            img->setAspectRatio(16.0f / 9.0f);
            img->setClipsToBounds(false);
            img->setCornerRadius(ist.borderRadius ? *ist.borderRadius : 6.f);
            img->setMarginTop(10); img->setMarginBottom(10);
            Box* imgContainer = new Box(Axis::ROW);
            imgContainer->setJustifyContent(JustifyContent::CENTER);
            imgContainer->setWidthPercentage(100);
            img->setWidthPercentage(80);
            imgContainer->addView(img);
            parent->addView(imgContainer);
            if (src.rfind("http", 0) == 0) {
                img->setImageAsync([src](std::function<void(const std::string&, size_t)> cb) {
                    SimpleHTTPClient::downloadImage(src, [cb](bool ok, const std::string& d) { if (ok) cb(d, d.size()); });
                });
            } else { img->setImageFromFile(src); }
        }
        skip = true;
    }

    // ── div / section / article etc. ─────────────────────────────────
    else if (tag == "div" || tag == "section" || tag == "article" ||
             tag == "main" || tag == "header" || tag == "footer" ||
             tag == "body" || tag == "html" || tag == "center" ||
             tag == "td"   || tag == "th") {

        // Check if div is a monospace code container
        bool isMonoDiv = false;
        if (tag == "div") {
            std::string ff = "";
            std::string styleStr = node->attributes.count("style") ? node->attributes.at("style") : "";
            std::istringstream ss2(styleStr); std::string seg2;
            while (std::getline(ss2, seg2, ';')) {
                size_t cp = seg2.find(':'); if (cp == std::string::npos) continue;
                std::string k = toLower(strTrim(seg2.substr(0,cp)));
                std::string v = strTrim(seg2.substr(cp+1));
                if (k == "font-family") ff = toLower(v);
            }
            isMonoDiv = (ff.find("monospace") != std::string::npos ||
                         ff.find("courier")   != std::string::npos);
        }

        if (isMonoDiv) {
            // Dark code block: render each <code> child with its own colour
            Box* darkBox = new Box(Axis::COLUMN);
            darkBox->setBackgroundColor(ist.backgroundColor ? *ist.backgroundColor : HAN_DARK_BG);
            darkBox->setCornerRadius(ist.borderRadius ? *ist.borderRadius : 6.f);
            darkBox->setPadding(ist.paddingTop ? *ist.paddingTop : 16);
            if (ist.marginBottom) darkBox->setMarginBottom(*ist.marginBottom);

            for (auto* child : node->children) {
                if (child->tag == "code") {
                    // Per-code colour
                    NVGcolor codeColor = nvgRGB(0xcd, 0xd6, 0xf4); // default light
                    std::string cstyle = child->attributes.count("style") ? child->attributes.at("style") : "";
                    if (!cstyle.empty()) {
                        std::istringstream ss3(cstyle); std::string seg3;
                        while (std::getline(ss3, seg3, ';')) {
                            size_t cp = seg3.find(':'); if (cp == std::string::npos) continue;
                            std::string k = toLower(strTrim(seg3.substr(0,cp)));
                            std::string v = strTrim(seg3.substr(cp+1));
                            if (k == "color") { auto col = parseColor(v); if (col) codeColor = *col; }
                        }
                    }
                    std::string codeTxt = collectText(child);
                    Label* lbl = makeLabel(codeTxt, BASE * 0.78f, codeColor);
                    darkBox->addView(lbl);
                } else if (child->tag == "br" || (child->isText && strTrim(child->text).empty())) {
                    Box* sp = new Box(Axis::ROW); sp->setHeight(4);
                    darkBox->addView(sp);
                }
            }
            parent->addView(darkBox);
            skip = true;
        } else {
            Box* db = new Box(Axis::COLUMN);
            renderer->applyStyle(db, ist);
            // text-align: center → JustifyContent on children managed per-row; store for inline wrapper
            parent->addView(db);
            cont = db;
        }
    }

    // ── Apply inline style overrides to cont (non-skipped paths) ──────
    if (!skip) {
        if (ist.marginTop)    cont->setMarginTop(*ist.marginTop);
        if (ist.marginBottom) cont->setMarginBottom(*ist.marginBottom);
        if (ist.marginLeft)   cont->setMarginLeft(*ist.marginLeft);
        if (ist.marginRight)  cont->setMarginRight(*ist.marginRight);
        if (ist.color)        currentTextColor = ist.color;
        if (ist.fontSize)     baseFontSize     = *ist.fontSize;

        Box* iRow = nullptr;
        for (auto* child : node->children) {
            if (isInlineNode(child)) {
                if (!iRow) {
                    iRow = new Box(Axis::ROW);
                    iRow->setFlexWrap(true); iRow->setRowGap(10);
                    iRow->setAlignItems(AlignItems::CENTER);
                    if (ist.textAlign) applyTextAlign(iRow, *ist.textAlign);
                    cont->addView(iRow);
                }
                renderInline(child, iRow, baseFontSize,
                    currentTextColor ? *currentTextColor : defaultTextColor);
            } else {
                iRow = nullptr;
                buildHtmlViews(renderer, child, cont, baseFontSize,
                               currentTextColor, defaultTextColor, accentColor);
            }
        }
    }

    baseFontSize     = oldSize;
    currentTextColor = oldColor;
}

// ============================================================
// renderString  —  entry point
// ============================================================
void HtmlRenderer::renderString(const std::string& html) {
    clearViews();
    MiniNode* root = parseHTML(html);
    NVGcolor def = HAN_TEXT;
    NVGcolor acc = HAN_EMERALD;
    float fs = baseFontSize;
    std::optional<NVGcolor> tc = customTextColor;
    buildHtmlViews(this, root, this, fs, tc, def, acc);
    delete root;
}

} // namespace brls
