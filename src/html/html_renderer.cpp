#include "view/html_renderer.hpp"
#include "network/http_client.hpp"
#include <borealis/core/logger.hpp>
#include <fstream>
#include <sstream>
#include <stack>
#include <algorithm>
#include "utils/image_utils.hpp"
#include <nanovg.h>

namespace brls {

// ============================================================
// han.css Color Palette
// ============================================================
static const NVGcolor HAN_TEXT         = nvgRGB(0x33, 0x33, 0x33); // #333
static const NVGcolor HAN_TEXT_BLACK   = nvgRGB(0x00, 0x00, 0x00); // headings
static const NVGcolor HAN_EMERALD      = nvgRGB(0x1a, 0xbc, 0x9c); // #1abc9c
static const NVGcolor HAN_QUOTE_TEXT   = nvgRGB(0x99, 0x99, 0x99); // #999
static const NVGcolor HAN_HR_COLOR     = nvgRGB(0xcf, 0xcf, 0xcf); // #cfcfcf
static const NVGcolor HAN_H1_BORDER    = nvgRGB(0xee, 0xee, 0xee); // #eee (double)
static const NVGcolor HAN_BORDER_DDD   = nvgRGB(0xdd, 0xdd, 0xdd); // #ddd
static const NVGcolor HAN_CODE_BG      = nvgRGBA(135, 131, 120, 38); // rgba(135,131,120,.15)
static const NVGcolor HAN_CODE_TEXT    = nvgRGB(0xEB, 0x57, 0x57); // #EB5757
static const NVGcolor HAN_STRONG_TEXT  = nvgRGB(0x00, 0x00, 0x00); // #000
static const NVGcolor HAN_TH_BG        = nvgRGB(0xf1, 0xf1, 0xf1); // #f1f1f1
static const NVGcolor HAN_TD_TEXT      = nvgRGB(0x66, 0x66, 0x66); // #666
static const NVGcolor HAN_PRE_BG       = nvgRGB(0xf5, 0xf5, 0xf5); // #f5f5f5 for code blocks

// ============================================================
// Base font size (16px equivalent) and scale factors from han.css
// ============================================================
static constexpr float BASE_FONT_PX   = 26.0f;  // baseline for regular text
static constexpr float H1_SCALE       = 2.4f;
static constexpr float H2_SCALE       = 1.8f;
static constexpr float H3_SCALE       = 1.6f;
static constexpr float H4_SCALE       = 1.4f;
static constexpr float H5_SCALE       = 1.2f;
static constexpr float CODE_SCALE     = 0.85f;

MiniNode::~MiniNode() {
    for (auto child : children) delete child;
}

HtmlRenderer::HtmlRenderer() {
    setAxis(Axis::COLUMN);
    setPadding(20);
}

HtmlRenderer::~HtmlRenderer() {}

HtmlRenderer* HtmlRenderer::create() {
    return new HtmlRenderer();
}

void HtmlRenderer::renderFile(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        Logger::error("HtmlRenderer: Could not open file {}", path);
        return;
    }
    std::stringstream buffer;
    buffer << file.rdbuf();
    renderString(buffer.str());
}

// ============================================================
// HTML Parser
// ============================================================
static MiniNode* parseHTMLInternal(const std::string& html) {
    MiniNode* root = new MiniNode();
    root->tag = "root";

    std::stack<MiniNode*> stack;
    stack.push(root);

    size_t i = 0;
    while (i < html.length()) {
        if (html[i] == '<') {
            size_t end = html.find('>', i);
            if (end == std::string::npos) break;

            std::string tagContent = html.substr(i + 1, end - i - 1);
            // Handle comments
            if (tagContent.substr(0, 3) == "!--") {
                i = end + 1;
                continue;
            }
            i = end + 1;

            if (tagContent.empty()) continue;

            if (tagContent[0] == '/') { // Closing tag
                if (stack.size() > 1) stack.pop();
            } else { // Opening tag
                bool selfClosing = (tagContent.back() == '/');
                if (selfClosing) tagContent.pop_back();
                if (!tagContent.empty() && tagContent.back() == ' ') tagContent.pop_back();

                std::stringstream ss(tagContent);
                std::string tagName;
                ss >> tagName;

                MiniNode* node = new MiniNode();
                node->tag = tagName;
                std::transform(node->tag.begin(), node->tag.end(), node->tag.begin(), ::tolower);

                // Parse attributes
                std::string remaining;
                std::getline(ss, remaining);
                // Simple attr parsing: key="value" or key='value'
                size_t pos = 0;
                while (pos < remaining.size()) {
                    // skip whitespace
                    while (pos < remaining.size() && isspace(remaining[pos])) pos++;
                    if (pos >= remaining.size()) break;

                    size_t eq = remaining.find('=', pos);
                    if (eq == std::string::npos) break;

                    std::string key = remaining.substr(pos, eq - pos);
                    // trim key
                    key.erase(key.find_last_not_of(" \t") + 1);
                    pos = eq + 1;
                    if (pos >= remaining.size()) break;

                    char quote = remaining[pos];
                    if (quote != '"' && quote != '\'') { pos++; continue; }
                    pos++;
                    size_t valEnd = remaining.find(quote, pos);
                    if (valEnd == std::string::npos) break;
                    std::string val = remaining.substr(pos, valEnd - pos);
                    node->attributes[key] = val;
                    pos = valEnd + 1;
                }

                stack.top()->children.push_back(node);
                const std::string& nt = node->tag;
                bool isVoid = (nt == "br" || nt == "img" || nt == "hr" || nt == "input" ||
                               nt == "meta" || nt == "link");
                if (!selfClosing && !isVoid) {
                    stack.push(node);
                }
            }
        } else {
            size_t next = html.find('<', i);
            std::string text = html.substr(i, (next == std::string::npos) ? std::string::npos : next - i);
            i = (next == std::string::npos) ? html.length() : next;

            if (text.find_first_not_of(" \t\n\r") != std::string::npos) {
                MiniNode* node = new MiniNode();
                node->isText = true;
                node->text = text;
                // Normalize whitespace: collapse runs of whitespace
                std::string normalized;
                bool lastWasSpace = false;
                for (char c : node->text) {
                    if (c == '\n' || c == '\r' || c == '\t') c = ' ';
                    if (c == ' ') {
                        if (!lastWasSpace && !normalized.empty()) {
                            normalized += c;
                            lastWasSpace = true;
                        }
                    } else {
                        normalized += c;
                        lastWasSpace = false;
                    }
                }
                node->text = normalized;
                if (!node->text.empty())
                    stack.top()->children.push_back(node);
                else
                    delete node;
            }
        }
    }

    return root;
}

static std::optional<NVGcolor> parseColor(const std::string& str) {
    if (str.empty()) return std::nullopt;
    if (str[0] == '#') {
        if (str.length() == 7) {
            int r, g, b;
            sscanf(str.c_str(), "#%02x%02x%02x", &r, &g, &b);
            return nvgRGB((unsigned char)r, (unsigned char)g, (unsigned char)b);
        }
    }
    if (str == "red")   return nvgRGB(255, 0, 0);
    if (str == "green") return nvgRGB(0, 128, 0);
    if (str == "blue")  return nvgRGB(0, 0, 255);
    if (str == "white") return nvgRGB(255, 255, 255);
    if (str == "black") return nvgRGB(0, 0, 0);
    return std::nullopt;
}

CssStyle HtmlRenderer::parseInlineStyle(const std::string& styleStr) {
    CssStyle style;
    std::stringstream ss(styleStr);
    std::string segment;
    while (std::getline(ss, segment, ';')) {
        size_t colon = segment.find(':');
        if (colon == std::string::npos) continue;
        std::string key = segment.substr(0, colon);
        std::string val = segment.substr(colon + 1);
        auto trim = [](std::string& s) {
            s.erase(0, s.find_first_not_of(" \t\n\r"));
            size_t last = s.find_last_not_of(" \t\n\r");
            if (last != std::string::npos) s.erase(last + 1);
        };
        trim(key);
        trim(val);
        if (key == "color") style.color = parseColor(val);
        else if (key == "font-size") {
            try { style.fontSize = std::stof(val) * (BASE_FONT_PX / 16.0f); }
            catch (...) {}
        }
        else if (key == "margin-top") {
            try { style.marginTop = std::stof(val); } catch (...) {}
        }
        else if (key == "margin-bottom") {
            try { style.marginBottom = std::stof(val); } catch (...) {}
        }
    }
    return style;
}

NVGcolor HtmlRenderer::getThemeColor(const std::string& key) {
    return Application::getTheme().getColor(key);
}

void HtmlRenderer::applyStyle(View* view, const CssStyle& style) {
    if (style.marginTop)    view->setMarginTop(*style.marginTop);
    if (style.marginBottom) view->setMarginBottom(*style.marginBottom);
    if (auto* label = dynamic_cast<Label*>(view)) {
        if (style.color)    label->setTextColor(*style.color);
        if (style.fontSize) label->setFontSize(*style.fontSize);
    }
}

// ============================================================
// Helper: collect all text inside a node (recursive)
// ============================================================
static std::string collectText(MiniNode* node) {
    if (node->isText) return node->text;
    std::string result;
    for (auto* c : node->children) result += collectText(c);
    return result;
}

static bool isInlineNode(MiniNode* node) {
    if (node->isText) return true;
    static const std::set<std::string> inlineTags = {
        "strong", "b", "i", "em", "span", "a", "u", "code", "font",
        "small", "big", "del", "s", "ins", "mark", "sup", "sub"
    };
    return inlineTags.count(node->tag) > 0;
}

// ============================================================
// Build a rich-text Label for inline content (bold/italic/color/etc.)
// ============================================================
static void buildInlineLabel(MiniNode* node, Box* parent, float baseFontSize,
                              NVGcolor textColor, NVGcolor defaultTextColor) {
    if (node->isText) {
        if (node->text.empty()) return;
        Label* lbl = new Label();
        lbl->setText(node->text);
        lbl->setFontSize(baseFontSize);
        lbl->setTextColor(textColor);
        parent->addView(lbl);
        return;
    }
    const std::string& t = node->tag;
    NVGcolor color = textColor;
    float fontSize = baseFontSize;
    bool isLink = false;
    std::string href;

    if (t == "strong" || t == "b") {
        color = HAN_STRONG_TEXT;
        fontSize *= 1.05f;
    } else if (t == "em" || t == "i") {
        // NanoVG doesn't have italic natively, best approximation is color shift
        color = nvgRGB(0x55, 0x55, 0x55);
    } else if (t == "del" || t == "s") {
        color = HAN_QUOTE_TEXT;
    } else if (t == "a") {
        color = HAN_EMERALD;
        isLink = true;
        href = node->attributes.count("href") ? node->attributes.at("href") : "";
    } else if (t == "code") {
        // Inline code: draw as a colored label in a rounded box
        Box* cBox = new Box(Axis::ROW);
        cBox->setBackgroundColor(HAN_CODE_BG);
        cBox->setCornerRadius(4);
        cBox->setPadding(2, 8, 2, 8);
        Label* cLbl = new Label();
        cLbl->setText(collectText(node));
        cLbl->setFontSize(baseFontSize * CODE_SCALE);
        cLbl->setTextColor(HAN_CODE_TEXT);
        cBox->addView(cLbl);
        parent->addView(cBox);
        return;
    } else if (t == "mark") {
        color = nvgRGB(0, 0, 0);
        // could set highlight bg but skip for simplicity
    }

    for (auto* child : node->children) {
        buildInlineLabel(child, parent, fontSize, color, defaultTextColor);
    }

    if (isLink) {
        // Overwrite: labels were already added by recursion. Add underline box after
        // to indicate it's a link visually, but for simplicity, just set color above.
        (void)href;
    }
}

// ============================================================
// Draw a thin horizontal line (hr element)
// han.css: border-bottom: 1px solid #cfcfcf; margin: 0.8em
// ============================================================
static Box* makeHR() {
    Box* hr = new Box(Axis::ROW);
    hr->setHeight(2.0f);
    hr->setBackgroundColor(HAN_HR_COLOR);
    hr->setMarginTop(20);
    hr->setMarginBottom(20);
    return hr;
}

// ============================================================
// Draw H1 with a DOUBLE bottom border (han.css: border-bottom: 3px double #eee)
// We simulate double by drawing two lines with a gap
// ============================================================
static Box* makeH1Container() {
    Box* box = new Box(Axis::COLUMN);
    box->setMarginTop(32);
    box->setMarginBottom(16);
    // Simulate "3px double" border-bottom via two stacked line boxes below
    return box;
}

// add the double border lines to an h1 container
static void addH1DoubleBorder(Box* container) {
    Box* line1 = new Box(Axis::ROW);
    line1->setHeight(1.5f);
    line1->setBackgroundColor(HAN_H1_BORDER);
    line1->setMarginTop(12);

    Box* gap = new Box(Axis::ROW);
    gap->setHeight(2.0f);

    Box* line2 = new Box(Axis::ROW);
    line2->setHeight(1.5f);
    line2->setBackgroundColor(HAN_H1_BORDER);

    container->addView(line1);
    container->addView(gap);
    container->addView(line2);
}

// ============================================================
// Build a table from a MiniNode representing <table>
// han.css: border-collapse, th bg #f1f1f1, td color #666
// ============================================================
static void buildTable(MiniNode* tableNode, Box* parent, float baseFontSize) {
    Box* tableBox = new Box(Axis::COLUMN);
    tableBox->setMarginBottom(20);
    tableBox->setBorderThickness(1);
    tableBox->setBorderColor(HAN_BORDER_DDD);

    for (auto* rowGroup : tableNode->children) {
        const std::string& rgTag = rowGroup->tag;
        if (rgTag != "thead" && rgTag != "tbody" && rgTag != "tfoot" && rgTag != "tr") continue;

        std::vector<MiniNode*> rows;
        if (rgTag == "tr") {
            rows.push_back(rowGroup);
        } else {
            for (auto* r : rowGroup->children) {
                if (r->tag == "tr") rows.push_back(r);
            }
        }

        for (auto* row : rows) {
            Box* rowBox = new Box(Axis::ROW);
            rowBox->setMarginBottom(0);

            for (auto* cell : row->children) {
                bool isHeader = (cell->tag == "th");
                Box* cellBox = new Box(Axis::COLUMN);
                cellBox->setGrow(1.0f);
                cellBox->setPadding(8, 16, 8, 16);
                cellBox->setBorderThickness(1);
                cellBox->setBorderColor(HAN_BORDER_DDD);

                if (isHeader) {
                    cellBox->setBackgroundColor(HAN_TH_BG);
                }

                Label* cellLbl = new Label();
                cellLbl->setText(collectText(cell));
                cellLbl->setFontSize(baseFontSize * (isHeader ? 0.90f : 0.85f));
                cellLbl->setTextColor(isHeader ? HAN_TEXT_BLACK : HAN_TD_TEXT);
                cellBox->addView(cellLbl);
                rowBox->addView(cellBox);
            }
            tableBox->addView(rowBox);
        }
    }
    parent->addView(tableBox);
}

// ============================================================
// Central recursive builder
// ============================================================
void HtmlRenderer::buildHtmlViews(HtmlRenderer* renderer, MiniNode* node, Box* parent,
                                  float& baseFontSize,
                                  std::optional<NVGcolor>& currentTextColor,
                                  const NVGcolor& defaultTextColor,
                                  const NVGcolor& accentColor) {
    if (node->isText) {
        Label* label = new Label();
        label->setText(node->text);
        label->setFontSize(baseFontSize);
        label->setTextColor(currentTextColor ? *currentTextColor : defaultTextColor);
        parent->addView(label);
        return;
    }

    float oldFontSize       = baseFontSize;
    auto  oldTextColor      = currentTextColor;
    Box*  currentContainer  = parent;
    bool  skipChildren      = false;

    CssStyle inlineStyle = renderer->parseInlineStyle(
        node->attributes.count("style") ? node->attributes.at("style") : "");

    NVGcolor textColor = currentTextColor ? *currentTextColor : defaultTextColor;

    // ──────────────── Block elements ────────────────

    // H1: font-size 2.4em, padding-bottom 1em, border-bottom 3px double #eee
    if (node->tag == "h1") {
        Box* hBox = makeH1Container();
        Label* lbl = new Label();
        lbl->setText(collectText(node));
        lbl->setFontSize(BASE_FONT_PX * H1_SCALE);
        lbl->setTextColor(HAN_TEXT_BLACK);
        hBox->addView(lbl);
        addH1DoubleBorder(hBox);
        parent->addView(hBox);
        skipChildren = true;
    }
    else if (node->tag == "h2") {
        Box* hBox = new Box(Axis::COLUMN);
        hBox->setMarginTop(26);
        hBox->setMarginBottom(10);
        Label* lbl = new Label();
        lbl->setText(collectText(node));
        lbl->setFontSize(BASE_FONT_PX * H2_SCALE);
        lbl->setTextColor(HAN_TEXT_BLACK);
        hBox->addView(lbl);
        parent->addView(hBox);
        skipChildren = true;
    }
    else if (node->tag == "h3") {
        Box* hBox = new Box(Axis::COLUMN);
        hBox->setMarginTop(20);
        hBox->setMarginBottom(8);
        Label* lbl = new Label();
        lbl->setText(collectText(node));
        lbl->setFontSize(BASE_FONT_PX * H3_SCALE);
        lbl->setTextColor(HAN_TEXT_BLACK);
        hBox->addView(lbl);
        parent->addView(hBox);
        skipChildren = true;
    }
    else if (node->tag == "h4") {
        Box* hBox = new Box(Axis::COLUMN);
        hBox->setMarginTop(16);
        hBox->setMarginBottom(6);
        Label* lbl = new Label();
        lbl->setText(collectText(node));
        lbl->setFontSize(BASE_FONT_PX * H4_SCALE);
        lbl->setTextColor(HAN_TEXT_BLACK);
        hBox->addView(lbl);
        parent->addView(hBox);
        skipChildren = true;
    }
    else if (node->tag == "h5" || node->tag == "h6") {
        Box* hBox = new Box(Axis::COLUMN);
        hBox->setMarginTop(14);
        hBox->setMarginBottom(4);
        Label* lbl = new Label();
        lbl->setText(collectText(node));
        lbl->setFontSize(BASE_FONT_PX * H5_SCALE);
        lbl->setTextColor(HAN_TEXT_BLACK);
        hBox->addView(lbl);
        parent->addView(hBox);
        skipChildren = true;
    }

    // P: margin-bottom 1.2em
    else if (node->tag == "p") {
        Box* pBox = new Box(Axis::ROW);
        pBox->setFlexWrap(true);
        pBox->setAlignItems(AlignItems::FLEX_START);
        pBox->setMarginBottom(22);
        for (auto* child : node->children) {
            buildInlineLabel(child, pBox, BASE_FONT_PX, textColor, defaultTextColor);
        }
        parent->addView(pBox);
        skipChildren = true;
    }

    // Blockquote: border-left 1px solid #1abc9c, color #999, padding-left 1em, margin-left 2em
    else if (node->tag == "blockquote") {
        Box* qBox = new Box(Axis::COLUMN);
        qBox->setLineLeft(3);
        qBox->setLineColor(HAN_EMERALD);
        qBox->setPaddingLeft(20);
        qBox->setPaddingTop(4);
        qBox->setPaddingBottom(4);
        qBox->setMarginTop(16);
        qBox->setMarginBottom(22);
        qBox->setMarginLeft(30);
        qBox->setMarginRight(50);
        currentContainer = qBox;
        currentTextColor = HAN_QUOTE_TEXT;
        parent->addView(qBox);
    }

    // UL: list-style disc, margin-left 1.3em
    else if (node->tag == "ul") {
        Box* listBox = new Box(Axis::COLUMN);
        listBox->setPaddingLeft(22);
        listBox->setMarginBottom(22);
        for (auto* child : node->children) {
            if (child->tag == "li") {
                Box* row = new Box(Axis::ROW);
                row->setAlignItems(AlignItems::FLEX_START);
                row->setMarginBottom(6);
                // Disc bullet (•)
                Label* bullet = new Label();
                bullet->setText("• ");
                bullet->setFontSize(BASE_FONT_PX);
                bullet->setTextColor(textColor);
                row->addView(bullet);
                // Content (may have nested inline or block)
                Box* content = new Box(Axis::ROW);
                content->setFlexWrap(true);
                content->setGrow(1.0f);
                content->setAlignItems(AlignItems::FLEX_START);
                for (auto* liChild : child->children) {
                    buildInlineLabel(liChild, content, BASE_FONT_PX, textColor, defaultTextColor);
                }
                row->addView(content);
                listBox->addView(row);
            }
        }
        parent->addView(listBox);
        skipChildren = true;
    }

    // OL: list-style decimal, margin-left 1.9em
    else if (node->tag == "ol") {
        Box* listBox = new Box(Axis::COLUMN);
        listBox->setPaddingLeft(30);
        listBox->setMarginBottom(22);
        int counter = 1;
        for (auto* child : node->children) {
            if (child->tag == "li") {
                Box* row = new Box(Axis::ROW);
                row->setAlignItems(AlignItems::FLEX_START);
                row->setMarginBottom(6);
                Label* numLbl = new Label();
                numLbl->setText(std::to_string(counter++) + ". ");
                numLbl->setFontSize(BASE_FONT_PX);
                numLbl->setTextColor(textColor);
                row->addView(numLbl);
                Box* content = new Box(Axis::ROW);
                content->setFlexWrap(true);
                content->setGrow(1.0f);
                content->setAlignItems(AlignItems::FLEX_START);
                for (auto* liChild : child->children) {
                    buildInlineLabel(liChild, content, BASE_FONT_PX, textColor, defaultTextColor);
                }
                row->addView(content);
                listBox->addView(row);
            }
        }
        parent->addView(listBox);
        skipChildren = true;
    }

    // TABLE
    else if (node->tag == "table") {
        buildTable(node, parent, BASE_FONT_PX);
        skipChildren = true;
    }

    // PRE / Code block: border 1px #ddd, padding 1em
    else if (node->tag == "pre") {
        Box* preBox = new Box(Axis::COLUMN);
        preBox->setBackgroundColor(HAN_PRE_BG);
        preBox->setBorderThickness(1);
        preBox->setBorderColor(HAN_BORDER_DDD);
        preBox->setCornerRadius(3);
        preBox->setPadding(16);
        preBox->setMarginBottom(22);
        // Gather text (may be <code> inside)
        std::string preText = collectText(node);
        Label* codeLbl = new Label();
        codeLbl->setText(preText);
        codeLbl->setFontSize(BASE_FONT_PX * CODE_SCALE);
        codeLbl->setTextColor(HAN_TEXT);
        preBox->addView(codeLbl);
        parent->addView(preBox);
        skipChildren = true;
    }

    // Code inline
    else if (node->tag == "code") {
        Box* cBox = new Box(Axis::ROW);
        cBox->setBackgroundColor(HAN_CODE_BG);
        cBox->setCornerRadius(4);
        cBox->setPadding(2, 8, 2, 8);
        Label* cLbl = new Label();
        cLbl->setText(collectText(node));
        cLbl->setFontSize(BASE_FONT_PX * CODE_SCALE);
        cLbl->setTextColor(HAN_CODE_TEXT);
        cBox->addView(cLbl);
        parent->addView(cBox);
        skipChildren = true;
    }

    // HR
    else if (node->tag == "hr") {
        parent->addView(makeHR());
        skipChildren = true;
    }

    // BR
    else if (node->tag == "br") {
        Box* spacer = new Box(Axis::ROW);
        spacer->setHeight(BASE_FONT_PX * 0.5f);
        parent->addView(spacer);
        skipChildren = true;
    }

    // A (anchor – block-level fallback)
    else if (node->tag == "a") {
        std::string href = node->attributes.count("href") ? node->attributes.at("href") : "";
        Label* link = new Label();
        link->setText(collectText(node));
        link->setFontSize(baseFontSize);
        link->setTextColor(HAN_EMERALD);
        // Add 1px bottom line via lineBottom
        link->setLineBottom(1);
        link->setLineColor(HAN_EMERALD);
        if (!href.empty()) {
            link->registerClickAction([href](View* v) {
                Application::getPlatform()->openBrowser(href);
                return true;
            });
        }
        parent->addView(link);
        skipChildren = true;
    }

    // IMG
    else if (node->tag == "img") {
        std::string src = node->attributes.count("src") ? node->attributes.at("src") : "";
        if (!src.empty()) {
            Image* image = new Image();
            image->setHeight(260);
            image->setCornerRadius(6);
            image->setMarginBottom(12);
            if (src.rfind("http", 0) == 0) {
                image->setImageAsync([src](std::function<void(const std::string&, size_t)> cb) {
                    SimpleHTTPClient::downloadImage(src, [cb](bool ok, const std::string& data) {
                        if (ok) cb(data, data.size());
                    });
                });
            } else {
                image->setImageFromFile(src);
            }
            parent->addView(image);
        }
        skipChildren = true;
    }

    // DIV / SECTION / ARTICLE: generic block
    else if (node->tag == "div" || node->tag == "section" || node->tag == "article" ||
             node->tag == "main" || node->tag == "header" || node->tag == "footer") {
        Box* dBox = new Box(Axis::COLUMN);
        parent->addView(dBox);
        currentContainer = dBox;
    }

    // SPAN / STRONG / EM / etc. (block fallback for inline tags used block-level)
    else if (node->tag == "strong" || node->tag == "b") {
        baseFontSize = oldFontSize * 1.05f;
        currentTextColor = HAN_STRONG_TEXT;
    }

    // Apply inline style overrides
    if (inlineStyle.marginTop)    currentContainer->setMarginTop(*inlineStyle.marginTop);
    if (inlineStyle.marginBottom) currentContainer->setMarginBottom(*inlineStyle.marginBottom);
    if (inlineStyle.color)        currentTextColor = inlineStyle.color;
    if (inlineStyle.fontSize)     baseFontSize = *inlineStyle.fontSize;

    if (!skipChildren) {
        Box* inlineWrapper = nullptr;
        for (auto* child : node->children) {
            if (isInlineNode(child)) {
                if (!inlineWrapper) {
                    inlineWrapper = new Box(Axis::ROW);
                    inlineWrapper->setAlignItems(AlignItems::CENTER);
                    inlineWrapper->setFlexWrap(true);
                    currentContainer->addView(inlineWrapper);
                }
                buildInlineLabel(child, inlineWrapper, baseFontSize,
                    currentTextColor ? *currentTextColor : defaultTextColor, defaultTextColor);
            } else {
                inlineWrapper = nullptr;
                buildHtmlViews(renderer, child, currentContainer, baseFontSize,
                    currentTextColor, defaultTextColor, accentColor);
            }
        }
    }

    baseFontSize   = oldFontSize;
    currentTextColor = oldTextColor;
}

void HtmlRenderer::renderString(const std::string& html) {
    clearViews();
    MiniNode* root = parseHTMLInternal(html);
    NVGcolor defaultTextColor = HAN_TEXT;
    NVGcolor accentColor      = HAN_EMERALD;

    float currentFontSize  = baseFontSize;
    std::optional<NVGcolor> currentTextColor = customTextColor;

    buildHtmlViews(this, root, this, currentFontSize, currentTextColor, defaultTextColor, accentColor);
    delete root;
}

} // namespace brls
