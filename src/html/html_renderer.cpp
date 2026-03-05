/*
 * html_renderer.cpp  —  HtmlRenderer
 *
 * Renders an HTML node tree as Borealis views.
 * Styling follows han.css closely.
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

namespace brls {

// ============================================================
// han.css colour palette
// ============================================================
static const NVGcolor HAN_TEXT        = nvgRGB(0x33, 0x33, 0x33);
static const NVGcolor HAN_BLACK       = nvgRGB(0x00, 0x00, 0x00);
static const NVGcolor HAN_EMERALD     = nvgRGB(0x1a, 0xbc, 0x9c); // #1abc9c
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

// han.css base font = 16px rendered; we use 26dp as our "1em"
static constexpr float BASE  = 26.0f;

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
// Utility
// ============================================================
static std::string strTrim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return {};
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
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
// HTML Parser  (minimal state-machine)
// ============================================================
static MiniNode* parseHTML(const std::string& html) {
    MiniNode* root = new MiniNode(); root->tag = "root";
    std::stack<MiniNode*> stk; stk.push(root);

    auto topNode = [&]() -> MiniNode* { return stk.top(); };

    size_t i = 0, n = html.size();
    while (i < n) {
        if (html[i] != '<') {
            // Text node
            size_t end = html.find('<', i);
            std::string raw = html.substr(i, end == std::string::npos ? std::string::npos : end - i);
            i = (end == std::string::npos) ? n : end;
            if (raw.find_first_not_of(" \t\n\r") == std::string::npos) continue;
            // Check if we are inside <pre>
            bool inPre = false;
            std::stack<MiniNode*> tempStack = stk;
            while (!tempStack.empty()) {
                if (tempStack.top()->tag == "pre") { inPre = true; break; }
                tempStack.pop();
            }

            if (inPre) {
                // Keep raw formatting
                MiniNode* tn = new MiniNode(); tn->isText = true; tn->text = raw;
                topNode()->children.push_back(tn);
            } else {
                // normalise whitespace
                std::string norm; bool sp = false;
                for (char c : raw) {
                    if (c == '\n' || c == '\r' || c == '\t') c = ' ';
                    if (c == ' ') { if (!sp && !norm.empty()) { norm += ' '; sp = true; } }
                    else { norm += c; sp = false; }
                }
                if (norm.empty()) continue;
                MiniNode* tn = new MiniNode(); tn->isText = true; tn->text = norm;
                topNode()->children.push_back(tn);
            }
            continue;
        }
        // Tag
        size_t end = html.find('>', i);
        if (end == std::string::npos) break;
        std::string tc = html.substr(i + 1, end - i - 1);
        i = end + 1;
        if (tc.empty()) continue;
        // Comment
        if (tc.substr(0, 3) == "!--") continue;
        // Closing tag
        if (tc[0] == '/') { if (stk.size() > 1) stk.pop(); continue; }

        // Opening tag
        bool sc = (!tc.empty() && tc.back() == '/');
        if (sc) tc.pop_back();
        if (!tc.empty() && tc.back() == ' ') tc.pop_back();

        std::istringstream iss(tc);
        std::string tagName; iss >> tagName;
        std::transform(tagName.begin(), tagName.end(), tagName.begin(), ::tolower);

        MiniNode* nd = new MiniNode(); nd->tag = tagName;

        // Parse attributes: handle key="val" and key='val'
        std::string rest; std::getline(iss, rest);
        size_t p = 0;
        while (p < rest.size()) {
            while (p < rest.size() && isspace((unsigned char)rest[p])) p++;
            if (p >= rest.size()) break;
            size_t eq = rest.find('=', p);
            if (eq == std::string::npos) break;
            std::string key = rest.substr(p, eq - p);
            // trim both ends of key
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
// CssStyle / parseInlineStyle
// ============================================================
static std::optional<NVGcolor> parseColor(const std::string& s) {
    if (s.size() == 7 && s[0] == '#') {
        int r, g, b;
        sscanf(s.c_str(), "#%02x%02x%02x", &r, &g, &b);
        return nvgRGB(r, g, b);
    }
    if (s=="red")   return nvgRGB(255,0,0);
    if (s=="green") return nvgRGB(0,128,0);
    if (s=="blue")  return nvgRGB(0,0,255);
    if (s=="white") return nvgRGB(255,255,255);
    if (s=="black") return nvgRGB(0,0,0);
    return std::nullopt;
}

CssStyle HtmlRenderer::parseInlineStyle(const std::string& css) {
    CssStyle st;
    std::istringstream ss(css); std::string seg;
    while (std::getline(ss, seg, ';')) {
        size_t c = seg.find(':'); if (c == std::string::npos) continue;
        std::string k = strTrim(seg.substr(0, c));
        std::string v = strTrim(seg.substr(c + 1));
        if (k == "color") st.color = parseColor(v);
        else if (k == "font-size") { try { st.fontSize = std::stof(v); } catch (...) {} }
        else if (k == "margin-top") { try { st.marginTop = std::stof(v); } catch (...) {} }
        else if (k == "margin-bottom") { try { st.marginBottom = std::stof(v); } catch (...) {} }
    }
    return st;
}

NVGcolor HtmlRenderer::getThemeColor(const std::string& key) {
    return Application::getTheme().getColor(key);
}

void HtmlRenderer::applyStyle(View* view, const CssStyle& st) {
    if (st.marginTop)    view->setMarginTop(*st.marginTop);
    if (st.marginBottom) view->setMarginBottom(*st.marginBottom);
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

// Simulate "3px double" h1 bottom border
static void attachH1Border(Box* container) {
    Box* l1 = new Box(Axis::ROW); l1->setHeight(1.5f); l1->setBackgroundColor(HAN_H1_BORDER); l1->setMarginTop(14);
    Box* gap = new Box(Axis::ROW); gap->setHeight(2.0f);
    Box* l2 = new Box(Axis::ROW); l2->setHeight(1.5f); l2->setBackgroundColor(HAN_H1_BORDER);
    container->addView(l1); container->addView(gap); container->addView(l2);
}

// ============================================================
// buildInlineContent — renders inline nodes into a flex-wrap ROW box
// Returns the row box (so caller can add it to main layout).
// ============================================================
static void renderInline(MiniNode* node, Box* target, float fontSize, NVGcolor color);

static void renderInlineChildren(const std::vector<MiniNode*>& children, Box* target,
                                  float fontSize, NVGcolor color) {
    for (auto* c : children) renderInline(c, target, fontSize, color);
}

static void renderInline(MiniNode* node, Box* target, float fontSize, NVGcolor color) {
    if (node->isText) {
        if (node->text.empty()) return;
        target->addView(makeLabel(node->text, fontSize, color));
        return;
    }

    const std::string& t = node->tag;

    if (t == "strong" || t == "b") {
        renderInlineChildren(node->children, target, fontSize, HAN_STRONG_TEXT);
    }
    else if (t == "em" || t == "i") {
        NVGcolor ec = nvgRGB(0x55, 0x55, 0x55);
        renderInlineChildren(node->children, target, fontSize, ec);
    }
    else if (t == "del" || t == "s") {
        renderInlineChildren(node->children, target, fontSize, HAN_DEL_TEXT);
    }
    else if (t == "code") {
        // Inline code box
        Box* cBox = new Box(Axis::ROW);
        cBox->setBackgroundColor(HAN_CODE_BG);
        cBox->setCornerRadius(4);
        cBox->setPadding(2, 8, 2, 8);
        cBox->addView(makeLabel(collectText(node), fontSize * 0.85f, HAN_CODE_TEXT));
        target->addView(cBox);
    }
    else if (t == "a") {
        std::string href = node->attributes.count("href") ? node->attributes.at("href") : "";
        std::string txt  = collectText(node);
        Label* lbl = makeLabel(txt, fontSize, HAN_EMERALD);
        lbl->setLineBottom(1);
        lbl->setLineColor(HAN_EMERALD);
        if (!href.empty()) {
            lbl->registerClickAction([href](View*) {
                Application::getPlatform()->openBrowser(href);
                return true;
            });
        }
        target->addView(lbl);
    }
    else if (t == "mark") {
        renderInlineChildren(node->children, target, fontSize, nvgRGB(0, 0, 0));
    }
    else if (t == "br") {
        // force a new paragraph-like break — insert a wide-enough invisible spacer
        Box* br = new Box(Axis::ROW); br->setHeight(fontSize * 0.5f);
        target->addView(br);
    }
    else if (t == "img") {
        std::string src = node->attributes.count("src") ? node->attributes.at("src") : "";
        if (!src.empty()) {
            Image* img = new Image();
            img->setHeight(240); // Base height scaled to row
            img->setCornerRadius(6);
            if (src.rfind("http", 0) == 0) {
                img->setImageAsync([src](std::function<void(const std::string&, size_t)> cb) {
                    SimpleHTTPClient::downloadImage(src, [cb](bool ok, const std::string& d) {
                        if (ok) cb(d, d.size());
                    });
                });
            } else {
                img->setImageFromFile(src);
            }
            target->addView(img);
        }
    }
    else {
        // Unknown inline / span — just recurse with same style
        renderInlineChildren(node->children, target, fontSize, color);
    }
}

// Creates a wrapping ROW box filled with the inline content of a block node
static Box* buildInlineRow(MiniNode* node, float fontSize, NVGcolor color) {
    Box* row = new Box(Axis::ROW);
    row->setFlexWrap(true);
    row->setRowGap(10); // Increases textual line spacing
    row->setColumnGap(0);
    row->setAlignItems(AlignItems::FLEX_START);
    renderInlineChildren(node->children, row, fontSize, color);
    return row;
}

// ============================================================
// Table builder
// ============================================================
static void buildTable(MiniNode* tableNode, Box* parent) {
    Box* tBox = new Box(Axis::COLUMN);
    tBox->setMarginBottom(22);
    tBox->setBorderThickness(1);
    tBox->setBorderColor(HAN_BORDER_DDD);

    // Collect rows
    std::vector<std::pair<bool, MiniNode*>> rows; // {isHeader, rowNode}
    std::function<void(MiniNode*, bool)> collect = [&](MiniNode* n, bool hdr) {
        for (auto* c : n->children) {
            if (c->tag == "tr") rows.push_back({hdr, c});
            else if (c->tag == "thead") collect(c, true);
            else if (c->tag == "tbody" || c->tag == "tfoot") collect(c, false);
        }
    };
    collect(tableNode, false);
    // also scan direct <tr> children
    for (auto* c : tableNode->children) if (c->tag == "tr") rows.push_back({false, c});

    for (auto& [hdr, row] : rows) {
        Box* rowBox = new Box(Axis::ROW);
        for (auto* cell : row->children) {
            if (cell->tag != "td" && cell->tag != "th") continue;
            bool isHdr = (cell->tag == "th") || hdr;
            Box* cellBox = new Box(Axis::COLUMN);
            cellBox->setGrow(1.0f);
            cellBox->setPadding(8, 16, 8, 16);
            cellBox->setBorderThickness(1);
            cellBox->setBorderColor(HAN_BORDER_DDD);
            if (isHdr) cellBox->setBackgroundColor(HAN_TH_BG);

            Box* content = buildInlineRow(cell, BASE * 0.85f,
                                          isHdr ? HAN_BLACK : HAN_TD_TEXT);
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

    // ── Headings ──────────────────────────────────────────────────────
    auto makeHeading = [&](float scale, bool doubleBottom) {
        Box* hb = new Box(Axis::COLUMN);
        hb->setMarginTop(scale >= 2.0f ? 32 : 22);
        hb->setMarginBottom(10);
        Box* row = buildInlineRow(node, BASE * scale, HAN_BLACK);
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
        Box* pb = buildInlineRow(node, BASE, textCol);
        pb->setMarginBottom(22);
        parent->addView(pb);
        skip = true;
    }

    // ── Blockquote ────────────────────────────────────────────────────
    else if (tag == "blockquote") {
        Box* qb = new Box(Axis::COLUMN);
        qb->setLineLeft(3);
        qb->setLineColor(HAN_EMERALD);
        qb->setPaddingLeft(20);
        qb->setPaddingTop(6);
        qb->setPaddingBottom(6);
        qb->setMarginTop(16);
        qb->setMarginBottom(22);
        qb->setMarginLeft(28);
        qb->setMarginRight(40);
        parent->addView(qb);
        cont = qb;
        currentTextColor = HAN_QUOTE_TEXT;
        // Render children into qb
        for (auto* child : node->children) {
            buildHtmlViews(renderer, child, cont, baseFontSize,
                           currentTextColor, defaultTextColor, accentColor);
        }
        skip = true;
    }

    // ── Lists ─────────────────────────────────────────────────────────
    else if (tag == "ul" || tag == "ol") {
        Box* lb = new Box(Axis::COLUMN);
        lb->setPaddingLeft(24);
        lb->setMarginBottom(22);
        int counter = 1;
        bool ordered = (tag == "ol");

        for (auto* liNode : node->children) {
            if (liNode->tag != "li") continue;

            Box* row = new Box(Axis::ROW);
            row->setAlignItems(AlignItems::FLEX_START);
            row->setMarginBottom(6);

            // Bullet / counter
            Label* marker = makeLabel(
                ordered ? (std::to_string(counter++) + ". ") : "• ",
                BASE, textCol);
            row->addView(marker);

            // Right side: column for inline text + potential nested list
            Box* rhs = new Box(Axis::COLUMN);
            rhs->setGrow(1.0f);

            Box* inlineRow  = nullptr; // lazy-created wrapping row for text runs

            for (auto* liChild : liNode->children) {
                if (liChild->tag == "ul" || liChild->tag == "ol") {
                    // Nested list — flush inline then recurse
                    inlineRow = nullptr;
                    buildHtmlViews(renderer, liChild, rhs, baseFontSize,
                                   currentTextColor, defaultTextColor, accentColor);
                } else if (isInlineNode(liChild)) {
                    if (!inlineRow) {
                        inlineRow = new Box(Axis::ROW);
                        inlineRow->setFlexWrap(true);
                        inlineRow->setRowGap(10); // Textual line spacing
                        inlineRow->setAlignItems(AlignItems::FLEX_START);
                        rhs->addView(inlineRow);
                    }
                    renderInline(liChild, inlineRow, BASE, textCol);
                } else {
                    inlineRow = nullptr;
                    buildHtmlViews(renderer, liChild, rhs, baseFontSize,
                                   currentTextColor, defaultTextColor, accentColor);
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
        buildTable(node, parent);
        skip = true;
    }

    // ── Pre / Code Block ──────────────────────────────────────────────
    else if (tag == "pre") {
        std::string lang;
        std::string codeText;
        // Look for inner <code class="lang-xxx">
        for (auto* c : node->children) {
            if (c->tag == "code") {
                lang = c->attributes.count("class") ? c->attributes.at("class") : "";
                if (lang.substr(0, 5) == "lang-") lang = lang.substr(5);
                codeText = collectText(c);
            } else {
                codeText += collectText(c);
            }
        }
        if (codeText.empty()) codeText = collectText(node);

        Box* preOuter = new Box(Axis::COLUMN);
        preOuter->setMarginBottom(22);
        preOuter->setBorderThickness(1);
        preOuter->setBorderColor(HAN_BORDER_DDD);
        preOuter->setCornerRadius(4);

        // Title bar: language + "Copy" button
        Box* titleBar = new Box(Axis::ROW);
        titleBar->setBackgroundColor(nvgRGB(0xe8, 0xe8, 0xe8));
        titleBar->setPadding(6, 12, 6, 12);
        titleBar->setAlignItems(AlignItems::CENTER);
        {
            Label* langLbl = makeLabel(lang.empty() ? "code" : lang, BASE * 0.75f, HAN_COPY_BTN);
            langLbl->setGrow(1.0f);
            titleBar->addView(langLbl);

            // Copy button (visual only — no clipboard API on Switch)
            Label* copyBtn = makeLabel("[ Copy ]", BASE * 0.72f, HAN_COPY_BTN);
            copyBtn->setFocusable(true);
            const std::string captured = codeText;
            copyBtn->registerClickAction([captured](View*) {
                // Desktop: put in clipboard if possible (no-op on Switch)
                Logger::info("Copy: {} chars", captured.size());
                return true;
            });
            titleBar->addView(copyBtn);
        }
        preOuter->addView(titleBar);

        // Code content
        Box* codeBox = new Box(Axis::COLUMN);
        codeBox->setBackgroundColor(HAN_PRE_BG);
        codeBox->setPadding(14);
        Label* codeLbl = makeLabel(codeText, BASE * 0.82f, HAN_TEXT);
        codeBox->addView(codeLbl);
        preOuter->addView(codeBox);

        parent->addView(preOuter);
        skip = true;
    }

    // ── Inline code (block-level fallback) ───────────────────────────
    else if (tag == "code") {
        Box* cb = new Box(Axis::ROW);
        cb->setBackgroundColor(HAN_CODE_BG);
        cb->setCornerRadius(4);
        cb->setPadding(2, 8, 2, 8);
        cb->addView(makeLabel(collectText(node), BASE * 0.85f, HAN_CODE_TEXT));
        parent->addView(cb);
        skip = true;
    }

    // ── HR ────────────────────────────────────────────────────────────
    else if (tag == "hr") {
        parent->addView(makeHR());
        skip = true;
    }

    // ── BR ────────────────────────────────────────────────────────────
    else if (tag == "br") {
        Box* spacer = new Box(Axis::ROW); spacer->setHeight(BASE * 0.5f);
        parent->addView(spacer);
        skip = true;
    }

    // ── Anchor (block-level) ──────────────────────────────────────────
    else if (tag == "a") {
        std::string href = node->attributes.count("href") ? node->attributes.at("href") : "";
        Label* lbl = makeLabel(collectText(node), baseFontSize, HAN_EMERALD);
        lbl->setLineBottom(1); lbl->setLineColor(HAN_EMERALD);
        if (!href.empty()) lbl->registerClickAction([href](View*) {
            Application::getPlatform()->openBrowser(href); return true;
        });
        parent->addView(lbl);
        skip = true;
    }

    // ── Image ─────────────────────────────────────────────────────────
    else if (tag == "img") {
        std::string src = node->attributes.count("src") ? node->attributes.at("src") : "";
        if (!src.empty()) {
            Image* img = new Image();
            img->setHeight(240);
            img->setCornerRadius(6);
            img->setMarginBottom(10);
            if (src.rfind("http", 0) == 0) {
                img->setImageAsync([src](std::function<void(const std::string&, size_t)> cb) {
                    SimpleHTTPClient::downloadImage(src, [cb](bool ok, const std::string& d) {
                        if (ok) cb(d, d.size());
                    });
                });
            } else {
                img->setImageFromFile(src);
            }
            parent->addView(img);
        }
        skip = true;
    }

    // ── Generic block containers ──────────────────────────────────────
    else if (tag == "div" || tag == "section" || tag == "article" ||
             tag == "main" || tag == "header" || tag == "footer" ||
             tag == "body" || tag == "html" || tag == "center") {
        Box* db = new Box(Axis::COLUMN);
        parent->addView(db);
        cont = db;
    }

    // Apply any inline style overrides
    if (ist.marginTop)    cont->setMarginTop(*ist.marginTop);
    if (ist.marginBottom) cont->setMarginBottom(*ist.marginBottom);
    if (ist.color)        currentTextColor = ist.color;
    if (ist.fontSize)     baseFontSize     = *ist.fontSize;

    // ── Recurse into children (if not already handled) ────────────────
    if (!skip) {
        Box* iRow = nullptr; // lazy inline wrapper
        for (auto* child : node->children) {
            if (isInlineNode(child)) {
                if (!iRow) {
                    iRow = new Box(Axis::ROW);
                    iRow->setFlexWrap(true);
                    iRow->setRowGap(10); // Textual line spacing
                    iRow->setAlignItems(AlignItems::CENTER);
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
