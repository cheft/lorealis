#include "view/html_view_builder.hpp"
#include "network/http_client.hpp"
#include "utils/image_utils.hpp"
#include <borealis/core/touch/tap_gesture.hpp>
#include <sstream>

namespace brls {

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

// Apply justification from textAlign string to a ROW box
static void applyTextAlign(Box* row, const std::string& align) {
    if (align == "center") row->setJustifyContent(JustifyContent::CENTER);
    else if (align == "right") row->setJustifyContent(JustifyContent::FLEX_END);
    else row->setJustifyContent(JustifyContent::FLEX_START);
}

void HtmlViewBuilder::applyStyle(View* view, const CssStyle& st) {
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
        if (st.borderRadius) {
            box->setCornerRadius(*st.borderRadius);
            if (*st.borderRadius > 0) box->setClipsToBounds(true);
        }
        if (st.overflowHidden && *st.overflowHidden) {
            box->setClipsToBounds(true);
        }
        if (st.opacity) box->setAlpha(*st.opacity);
        if (st.borderWidth && st.borderColor) {
            box->setBorderThickness(*st.borderWidth);
            box->setBorderColor(*st.borderColor);
        }

        if (st.width)           box->setWidth(*st.width);
        if (st.widthPercentage)  box->setWidthPercentage(*st.widthPercentage);
        if (st.height)          box->setHeight(*st.height);
        if (st.heightPercentage) box->setHeightPercentage(*st.heightPercentage);
    }

    // Label-level
    if (auto* lbl = dynamic_cast<Label*>(view)) {
        if (st.color)    lbl->setTextColor(*st.color);
        if (st.fontSize) {
             lbl->setFontSize(*st.fontSize);
             // Also scale line height if available
             lbl->setLineHeight(*st.fontSize * 1.5f);
        }
    }
}

void HtmlViewBuilder::renderInline(MiniNode* node, Box* target, float fontSize, NVGcolor color, bool strikethrough) {
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
        l->setLineHeight(fontSize * 1.5f);
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
            CssStyle sSt = HtmlStyle::parseInlineStyle(styleStr);
            if (sSt.color) spanColor = *sSt.color;
            if (sSt.textDecorationLine && *sSt.textDecorationLine) spanStrike = true;
        }
        renderInlineChildren(node->children, target, fontSize, spanColor, spanStrike);
    }
    else if (t == "code") {
        // Check for per-code colour (used in monospace div blocks)
        NVGcolor codeColor = HAN_CODE_TEXT;
        if (node->attributes.count("style")) {
            CssStyle st = HtmlStyle::parseInlineStyle(node->attributes.at("style"));
            if (st.color) codeColor = *st.color;
        }
        Box* cBox = new Box(Axis::ROW);
        cBox->setBackgroundColor(HAN_CODE_BG);
        cBox->setCornerRadius(4);
        cBox->setPadding(2, 8, 2, 8);
        Label* cl = makeLabel(HtmlParser::collectText(node), fontSize * 0.85f, codeColor);
        cBox->addView(cl);
        target->addView(cBox);
    }
    else if (t == "a") {
        std::string href = node->attributes.count("href") ? node->attributes.at("href") : "";
        std::string styleStr = node->attributes.count("style") ? node->attributes.at("style") : "";
        CssStyle aSt = HtmlStyle::parseInlineStyle(styleStr);
        
        bool isButton = aSt.backgroundColor.has_value() || aSt.borderWidth.has_value() || aSt.paddingTop.has_value() ||
                        styleStr.find("padding") != std::string::npos; // Fallback heuristic

        if (isButton) {
            Box* btnBox = new Box(Axis::ROW);
            btnBox->setJustifyContent(JustifyContent::CENTER);
            btnBox->setAlignItems(AlignItems::CENTER);
            applyStyle(btnBox, aSt);

            NVGcolor lblColor = aSt.color ? *aSt.color : (aSt.backgroundColor ? nvgRGB(255,255,255) : HAN_LINK_BLUE);
            float lblSize = aSt.fontSize ? *aSt.fontSize : fontSize;
            Label* lbl = makeLabel(HtmlParser::collectText(node), lblSize, lblColor);
            btnBox->addView(lbl);

            if (!href.empty()) {
                btnBox->setFocusable(true);
                btnBox->registerClickAction([href](View*) { Application::getPlatform()->openBrowser(href); return true; });
                btnBox->addGestureRecognizer(new TapGestureRecognizer([href](TapGestureStatus s, Sound*) {
                    if (s.state == GestureState::END) Application::getPlatform()->openBrowser(href);
                }));
            }
            target->addView(btnBox);
        } else {
            NVGcolor linkColor = aSt.color ? *aSt.color : HAN_LINK_BLUE;
            Label* lbl = makeLabel(HtmlParser::collectText(node), fontSize, linkColor);
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
    }
    else if (t == "br") {
        Box* br = new Box(Axis::ROW); br->setHeight(fontSize * 0.5f);
        target->addView(br);
    }
    else if (t == "img") {
        std::string src = node->attributes.count("src") ? node->attributes.at("src") : "";
        std::string styleStr = node->attributes.count("style") ? node->attributes.at("style") : "";
        CssStyle imgSt = HtmlStyle::parseInlineStyle(styleStr);

        if (!src.empty()) {
            Image* img = new Image();
            img->setScalingType(ImageScalingType::FIT); // Aspect ratio preserved

            // Let it determine its own height based on width. We skip hardcoding aspect ratio now, FIT behavior will scale height 
            // dynamically if we don't force a static height, or it'll just fit within the parent bound.
            img->setClipsToBounds(false);
            img->setCornerRadius(imgSt.borderRadius ? *imgSt.borderRadius : 6.f);
            
            Box* imgContainer = new Box(Axis::COLUMN);
            imgContainer->setJustifyContent(JustifyContent::FLEX_START);
            imgContainer->setAlignItems(AlignItems::CENTER);
            
            // Map the parsed style properties if they exist
            applyStyle(imgContainer, imgSt);

            if (!imgSt.marginTop) imgContainer->setMarginTop(12);
            if (!imgSt.marginBottom) imgContainer->setMarginBottom(12);

            // Container takes 100% horizontally, but allows height to grow.
            imgContainer->setWidthPercentage(100);
            
            // Image spans the container width based on max-width rule from HTML test page
            img->setWidthPercentage(100);
            // img->setGrow(1.0f); // Removed as it causes vertical expansion in flex parents

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

void HtmlViewBuilder::renderInlineChildren(const std::vector<MiniNode*>& children, Box* target,
                                  float fontSize, NVGcolor color, bool strikethrough) {
    for (auto* c : children) renderInline(c, target, fontSize, color, strikethrough);
}

Box* HtmlViewBuilder::buildInlineRow(MiniNode* node, float fontSize, NVGcolor color, const std::string& align) {
    Box* row = new Box(Axis::ROW);
    row->setFlexWrap(true);
    row->setWidthPercentage(100);
    row->setRowGap(10);
    row->setColumnGap(0);
    row->setAlignItems(AlignItems::FLEX_START);
    applyTextAlign(row, align);
    renderInlineChildren(node->children, row, fontSize, color);
    return row;
}

void HtmlViewBuilder::buildTable(MiniNode* tableNode, Box* parent,
                       float& baseFontSize,
                       std::optional<NVGcolor>& currentTextColor,
                       const NVGcolor& defaultTextColor,
                       const NVGcolor& accentColor) {
    Box* tBox = new Box(Axis::COLUMN);
    tBox->setMarginBottom(22);
    tBox->setAlignItems(AlignItems::STRETCH);

    // Parse attributes
    std::string tableWidth = tableNode->attributes.count("width") ? tableNode->attributes.at("width") : "";
    std::string tableBorder = tableNode->attributes.count("border") ? tableNode->attributes.at("border") : "";
    std::string tableCellPad = tableNode->attributes.count("cellpadding") ? tableNode->attributes.at("cellpadding") : "";

    bool hasBorder = (tableBorder != "" && tableBorder != "0");
    if (hasBorder) {
        tBox->setBorderThickness(1.0f);
        tBox->setBorderColor(HAN_BORDER_DDD);
    }

    if (!tableWidth.empty()) {
        if (tableWidth.back() == '%') {
            try { tBox->setWidthPercentage(std::stof(tableWidth.substr(0, tableWidth.size() - 1))); } catch(...) {}
        } else {
            // It's a precise dp value
            try { tBox->setWidth(std::stof(tableWidth)); } catch(...) {}
            tBox->setAlignSelf(AlignSelf::CENTER); // Usually layout tables are centered if they don't cover full width
        }
    } else {
        tBox->setWidthPercentage(100);
    }

    float defPadding = 8.0f;
    if (!tableCellPad.empty()) {
        try { defPadding = std::stof(tableCellPad); } catch(...) {}
    }

    std::vector<std::pair<bool, MiniNode*>> rows;
    std::function<void(MiniNode*, bool)> collect = [&](MiniNode* n, bool hdr) {
        for (auto* c : n->children) {
            if (c->tag == "tr") rows.push_back({hdr, c});
            else if (c->tag == "thead") collect(c, true);
            else if (c->tag == "tbody" || c->tag == "tfoot") collect(c, false);
        }
    };
    collect(tableNode, false);

    CssStyle tableSt = HtmlStyle::parseInlineStyle(
        tableNode->attributes.count("style") ? tableNode->attributes.at("style") : "");
    if (tableSt.backgroundColor) tBox->setBackgroundColor(*tableSt.backgroundColor);
    if (tableSt.borderRadius) { 
        tBox->setCornerRadius(*tableSt.borderRadius);
        if (*tableSt.borderRadius > 0) tBox->setClipsToBounds(true);
    }
    if (tableSt.marginTop)       tBox->setMarginTop(*tableSt.marginTop);
    if (tableSt.marginBottom)    tBox->setMarginBottom(*tableSt.marginBottom);
    if (tableSt.borderWidth && tableSt.borderColor) {
        tBox->setBorderThickness(*tableSt.borderWidth);
        tBox->setBorderColor(*tableSt.borderColor);
    }

    if (tableWidth == "600" || (!tableWidth.empty() && tableWidth.back() != '%')) {
         // Auto margin equivalent, push it to center if parent has AlignItems stretch
         tBox->setAlignSelf(AlignSelf::CENTER);
    }

    for (auto& [hdr, row] : rows) {
        CssStyle rowSt = HtmlStyle::parseInlineStyle(
            row->attributes.count("style") ? row->attributes.at("style") : "");

        Box* rowBox = new Box(Axis::ROW);

        int cols = 0;
        for (auto* c : row->children) if (c->tag == "td" || c->tag == "th") cols++;
        if (cols == 0) cols = 1;

        for (auto* cell : row->children) {
            if (cell->tag != "td" && cell->tag != "th") continue;
            bool isHdr = (cell->tag == "th") || hdr;

            std::string stText = cell->attributes.count("style") ? cell->attributes.at("style") : "";
            CssStyle cellSt = HtmlStyle::parseInlineStyle(stText);

            std::string cellWidth = cell->attributes.count("width") ? cell->attributes.at("width") : "";
            std::string cellHeight = cell->attributes.count("height") ? cell->attributes.at("height") : "";
            std::string cellAlign = cell->attributes.count("align") ? HtmlParser::toLower(cell->attributes.at("align")) : "";
            std::string cellValign = cell->attributes.count("valign") ? HtmlParser::toLower(cell->attributes.at("valign")) : "";

            Box* cellBox = new Box(Axis::COLUMN);

            if (!cellWidth.empty()) {
                if (cellWidth.back() == '%') {
                    try { cellBox->setWidthPercentage(std::stof(cellWidth.substr(0, cellWidth.size() - 1))); } catch(...) {}
                } else {
                    try { cellBox->setWidth(std::stof(cellWidth)); cellBox->setGrow(0.0f); } catch(...) {}
                }
            } else {
                cellBox->setGrow(1.0f);
            }

            if (!cellHeight.empty()) {
                if (cellHeight.back() == '%') {
                    try { cellBox->setHeightPercentage(std::stof(cellHeight.substr(0, cellHeight.size() - 1))); } catch(...) {}
                } else {
                    try { cellBox->setHeight(std::stof(cellHeight)); } catch(...) {}
                }
            }

            if (cellSt.paddingTop) cellBox->setPaddingTop(*cellSt.paddingTop);
            else cellBox->setPaddingTop(defPadding);
            
            if (cellSt.paddingBottom) cellBox->setPaddingBottom(*cellSt.paddingBottom);
            else cellBox->setPaddingBottom(defPadding);
            
            if (cellSt.paddingLeft) cellBox->setPaddingLeft(*cellSt.paddingLeft);
            else cellBox->setPaddingLeft(defPadding);
            
            if (cellSt.paddingRight) cellBox->setPaddingRight(*cellSt.paddingRight);
            else cellBox->setPaddingRight(defPadding);

            if (hasBorder) {
                // If the table wants borders, but cell didn't specify one, use generic color
                if (!cellSt.borderWidth) cellBox->setBorderThickness(1);
                if (!cellSt.borderColor) cellBox->setBorderColor(HAN_BORDER_DDD);
            }

            cellBox->setMarginTop(0); cellBox->setMarginBottom(0);

            if (cellSt.backgroundColor) cellBox->setBackgroundColor(*cellSt.backgroundColor);
            else if (rowSt.backgroundColor) cellBox->setBackgroundColor(*rowSt.backgroundColor);
            else if (isHdr && hasBorder) cellBox->setBackgroundColor(HAN_TH_BG);

            // Per cell border override
            if (cellSt.borderWidth && cellSt.borderColor) {
                cellBox->setBorderThickness(*cellSt.borderWidth);
                cellBox->setBorderColor(*cellSt.borderColor);
            } else if (cellSt.borderColor) {
                // User forced bottom border via bottom-border
                cellBox->setBorderThickness(1);
                cellBox->setBorderColor(*cellSt.borderColor);
            } else if (cellSt.borderWidth) {
                cellBox->setBorderThickness(*cellSt.borderWidth);
                cellBox->setBorderColor(HAN_BORDER_DDD);
            }

            std::string textAlignment = cellSt.textAlign ? *cellSt.textAlign : (cellAlign.empty() ? "left" : cellAlign);
            if (textAlignment == "center") cellBox->setAlignItems(AlignItems::CENTER);
            else if (textAlignment == "right") cellBox->setAlignItems(AlignItems::FLEX_END);
            else cellBox->setAlignItems(AlignItems::FLEX_START);

            if (cellValign == "middle") cellBox->setJustifyContent(JustifyContent::CENTER);
            else if (cellValign == "bottom") cellBox->setJustifyContent(JustifyContent::FLEX_END);
            else cellBox->setJustifyContent(JustifyContent::FLEX_START);

            NVGcolor cCol = cellSt.color ? *cellSt.color : (isHdr ? HAN_BLACK : HAN_TD_TEXT);
            std::optional<NVGcolor> localTextColor = cCol;

            // Recursively build elements
            Box* inlineRow = nullptr;
            for (auto* child : cell->children) {
                if (HtmlParser::isInlineNode(child)) {
                    if (!inlineRow) {
                         inlineRow = new Box(Axis::ROW);
                         inlineRow->setFlexWrap(true); inlineRow->setRowGap(10);
                         inlineRow->setAlignItems(AlignItems::FLEX_START);
                         if (textAlignment == "center") inlineRow->setJustifyContent(JustifyContent::CENTER);
                         else if (textAlignment == "right") inlineRow->setJustifyContent(JustifyContent::FLEX_END);
                         else inlineRow->setJustifyContent(JustifyContent::FLEX_START);
                         cellBox->addView(inlineRow);
                    }
                    renderInline(child, inlineRow, baseFontSize * 0.85f, cCol);
                } else {
                    inlineRow = nullptr;
                    buildHtmlViews(child, cellBox, baseFontSize, localTextColor, defaultTextColor, accentColor);
                }
            }

            // Bottom border simulation for cells
            if (stText.find("border-bottom") != std::string::npos && cellSt.borderColor && cellSt.borderWidth) {
                 Box* cellDivider = new Box(Axis::ROW);
                 cellDivider->setHeight(*cellSt.borderWidth);
                 cellDivider->setBackgroundColor(*cellSt.borderColor);
                 cellBox->addView(cellDivider);
            }

            rowBox->addView(cellBox);
        }
        tBox->addView(rowBox);
    }
    parent->addView(tBox);
}

void HtmlViewBuilder::buildHtmlViews(MiniNode* node, Box* parent,
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
 
    CssStyle ist = HtmlStyle::parseInlineStyle(
        node->attributes.count("style") ? node->attributes.at("style") : "");

    // Merge direct width/height attributes ONLY for specific tags if not in style
    if (tag == "img" || tag == "table" || tag == "td" || tag == "th") {
        if (!ist.width && node->attributes.count("width")) {
            std::string val = node->attributes.at("width");
            if (!val.empty() && val.back() == '%') {
                 try { ist.widthPercentage = std::stof(val.substr(0, val.size()-1)); } catch(...) {}
            } else {
                 try { ist.width = std::stof(val); } catch(...) {}
            }
        }
        if (!ist.height && node->attributes.count("height")) {
            std::string val = node->attributes.at("height");
            if (!val.empty() && val.back() == '%') {
                 try { ist.heightPercentage = std::stof(val.substr(0, val.size()-1)); } catch(...) {}
            } else {
                 try { ist.height = std::stof(val); } catch(...) {}
            }
        }
    }

    // Pull colour/size from inline style early for headings / p
    NVGcolor hColor = ist.color ? *ist.color : textCol;
    std::string hAlign = ist.textAlign ? *ist.textAlign : "left";

    // ── Headings ──────────────────────────────────────────────────────
    auto makeHeading = [&](float scale) {
        Box* hb = new Box(Axis::COLUMN);
        hb->setWidthPercentage(100);
        hb->setMarginTop(ist.marginTop ? *ist.marginTop : 14);
        hb->setMarginBottom(ist.marginBottom ? *ist.marginBottom : 8);
        
        float calculatedSize = ist.fontSize ? *ist.fontSize : (BASE * scale);
        Box* row = buildInlineRow(node, calculatedSize, hColor, hAlign);
        hb->addView(row);
        
        std::string stTextHead = node->attributes.count("style") ? node->attributes.at("style") : "";
        if ((ist.borderColor && ist.borderWidth) || stTextHead.find("border-bottom") != std::string::npos) {
             Box* dividerLine = new Box(Axis::ROW);
             dividerLine->setHeight(ist.borderWidth ? *ist.borderWidth : 1.0f);
             dividerLine->setBackgroundColor(ist.borderColor ? *ist.borderColor : HAN_BORDER_DDD);
             dividerLine->setMarginTop(8);
             hb->addView(dividerLine);
        }

        parent->addView(hb);
        skip = true;
    };

    if      (tag == "h1") makeHeading(1.8f);
    else if (tag == "h2") makeHeading(1.4f);
    else if (tag == "h3") makeHeading(1.2f);
    else if (tag == "h4" || tag == "h5" || tag == "h6") makeHeading(1.0f);

    // ── Paragraph ─────────────────────────────────────────────────────
    else if (tag == "p") {
        NVGcolor pCol = ist.color ? *ist.color : textCol;
        Box* pOuter = new Box(Axis::COLUMN);
        pOuter->setWidthPercentage(100);
        pOuter->setMarginBottom(ist.marginBottom ? *ist.marginBottom : 14);
        if (ist.marginTop) pOuter->setMarginTop(*ist.marginTop);
        
        Box* pb = buildInlineRow(node, ist.fontSize ? *ist.fontSize : BASE, pCol, hAlign);
        pOuter->addView(pb);

        std::string stTextP = node->attributes.count("style") ? node->attributes.at("style") : "";
        if (stTextP.find("border-bottom") != std::string::npos && ist.borderColor) {
             Box* div = new Box(Axis::ROW);
             div->setHeight(ist.borderWidth ? *ist.borderWidth : 1.0f);
             div->setBackgroundColor(*ist.borderColor);
             div->setMarginTop(8);
             pOuter->addView(div);
        }

        parent->addView(pOuter);
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
            buildHtmlViews(child, cont, baseFontSize, currentTextColor, defaultTextColor, accentColor);
        skip = true;
    }

    // ── Lists ─────────────────────────────────────────────────────────
    else if (tag == "ul" || tag == "ol") {
        Box* lb = new Box(Axis::COLUMN);
        lb->setWidthPercentage(100);
        lb->setPaddingLeft(ist.paddingLeft ? *ist.paddingLeft : 24);
        lb->setMarginBottom(ist.marginBottom ? *ist.marginBottom : 22);
        if (ist.marginTop) lb->setMarginTop(*ist.marginTop);
        int counter = 1;
        bool ordered = (tag == "ol");

        for (auto* liNode : node->children) {
            if (liNode->tag != "li") continue;
            bool hasContent = false;
            for (auto* c : liNode->children) if (HtmlParser::isInlineNode(c)) { hasContent = true; break; }
            if (liNode->children.empty()) hasContent = true;

            Box* row = new Box(Axis::ROW);
            row->setAlignItems(AlignItems::FLEX_START);
            row->setMarginBottom(6);

            float fSize = ist.fontSize ? *ist.fontSize : BASE;

            if (hasContent) {
                Label* marker = makeLabel(ordered ? (std::to_string(counter++) + ". ") : "• ", fSize, textCol);
                row->addView(marker);
            }

            Box* rhs = new Box(Axis::COLUMN); rhs->setGrow(1.0f);
            Box* inlineRow = nullptr;
            for (auto* liChild : liNode->children) {
                if (liChild->tag == "ul" || liChild->tag == "ol") {
                    inlineRow = nullptr;
                    buildHtmlViews(liChild, rhs, baseFontSize, currentTextColor, defaultTextColor, accentColor);
                } else if (HtmlParser::isInlineNode(liChild)) {
                    if (!inlineRow) {
                        inlineRow = new Box(Axis::ROW);
                        inlineRow->setFlexWrap(true); inlineRow->setRowGap(10);
                        inlineRow->setAlignItems(AlignItems::FLEX_START);
                        rhs->addView(inlineRow);
                    }
                    renderInline(liChild, inlineRow, fSize, textCol);
                } else {
                    inlineRow = nullptr;
                    buildHtmlViews(liChild, rhs, baseFontSize, currentTextColor, defaultTextColor, accentColor);
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
        buildTable(node, parent, baseFontSize, currentTextColor, defaultTextColor, accentColor);
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
                codeText = HtmlParser::collectText(c);
            } else { codeText += HtmlParser::collectText(c); }
        }
        if (codeText.empty()) codeText = HtmlParser::collectText(node);

        Box* preOuter = new Box(Axis::COLUMN);
        preOuter->setMarginBottom(22);
        preOuter->setBorderThickness(1); preOuter->setBorderColor(HAN_BORDER_DDD);
        preOuter->setCornerRadius(4);
        preOuter->setClipsToBounds(true);

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
        cb->addView(makeLabel(HtmlParser::collectText(node), BASE*0.85f, codeColor));
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

    // ── Anchor block-level ─────────────────────────────────────────────
    // Note: Due to isInlineTag("a"), <a> tags are now handled by renderInline!
    // This block is only a fallback for <a> parsing directly into buildHtmlViews.
    else if (tag == "a") {
        std::string href = node->attributes.count("href") ? node->attributes.at("href") : "";
        NVGcolor linkColor = ist.color ? *ist.color : HAN_LINK_BLUE;
        Label* lbl = makeLabel(HtmlParser::collectText(node), baseFontSize, linkColor);
        lbl->setLineBottom(1); lbl->setLineColor(linkColor);
        if (!href.empty()) {
            lbl->setFocusable(true);
            lbl->registerClickAction([href](View*) { Application::getPlatform()->openBrowser(href); return true; });
            lbl->addGestureRecognizer(new TapGestureRecognizer([href](TapGestureStatus s, Sound*) {
                if (s.state == GestureState::END) Application::getPlatform()->openBrowser(href);
            }));
        }
        parent->addView(lbl);
        skip = true;
    }

    // ── Image ─────────────────────────────────────────────────────────
    else if (tag == "img") {
        std::string src = node->attributes.count("src") ? node->attributes.at("src") : "";
        if (!src.empty()) {
            Image* img = new Image();
            img->setScalingType(ImageScalingType::FIT);

            // Removing fixed aspect ratio to allow natural proportional scaling
            
            img->setClipsToBounds(false);
            img->setCornerRadius(ist.borderRadius ? *ist.borderRadius : 6.f);
            
            Box* imgContainer = new Box(Axis::COLUMN);
            imgContainer->setJustifyContent(JustifyContent::FLEX_START);
            imgContainer->setAlignItems(AlignItems::CENTER);
            
            applyStyle(imgContainer, ist);
            
            if (!ist.marginTop) imgContainer->setMarginTop(10);
            if (!ist.marginBottom) imgContainer->setMarginBottom(10);
            
            imgContainer->setWidthPercentage(100);
            img->setWidthPercentage(100);
            // img->setGrow(1.0f); // Keep this removed! Vertical grow in COLUMN is bad.
            
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
                std::string k = HtmlParser::toLower(HtmlParser::strTrim(seg2.substr(0,cp)));
                std::string v = HtmlParser::strTrim(seg2.substr(cp+1));
                if (k == "font-family") ff = HtmlParser::toLower(v);
            }
            isMonoDiv = (ff.find("monospace") != std::string::npos ||
                         ff.find("courier")   != std::string::npos);
        }

        if (isMonoDiv) {
            // Dark code block: render each <code> child with its own colour
            Box* darkBox = new Box(Axis::COLUMN);
            darkBox->setBackgroundColor(ist.backgroundColor ? *ist.backgroundColor : HAN_DARK_BG);
            darkBox->setCornerRadius(ist.borderRadius ? *ist.borderRadius : 6.f);
            if (ist.borderRadius && *ist.borderRadius > 0) darkBox->setClipsToBounds(true);
            darkBox->setPadding(ist.paddingTop ? *ist.paddingTop : 16);
            if (ist.marginBottom) darkBox->setMarginBottom(*ist.marginBottom);

            for (auto* child : node->children) {
                if (child->tag == "code") {
                    // Per-code colour
                    NVGcolor codeColor = nvgRGB(0xcd, 0xd6, 0xf4); // default light
                    std::string cstyle = child->attributes.count("style") ? child->attributes.at("style") : "";
                    if (!cstyle.empty()) {
                        CssStyle cst = HtmlStyle::parseInlineStyle(cstyle);
                        if(cst.color) codeColor = *cst.color;
                    }
                    std::string codeTxt = HtmlParser::collectText(child);
                    Label* lbl = makeLabel(codeTxt, BASE * 0.78f, codeColor);
                    darkBox->addView(lbl);
                } else if (child->tag == "br" || (child->isText && HtmlParser::strTrim(child->text).empty())) {
                    Box* sp = new Box(Axis::ROW); sp->setHeight(4);
                    darkBox->addView(sp);
                }
            }
            parent->addView(darkBox);
            skip = true;
        } else {
            Box* db = new Box(Axis::COLUMN);
            db->setWidthPercentage(100); 
            db->setAlignItems(AlignItems::STRETCH);
            applyStyle(db, ist);
            parent->addView(db);
            cont = db;
        }
    }

    // ── Apply inline style overrides to cont (non-skipped paths) ──────
    if (!skip) {
        // Most margins / pads were applied in applyStyle() above for blocks
        if (ist.color)        currentTextColor = ist.color;
        if (ist.fontSize)     baseFontSize     = *ist.fontSize;

        Box* iRow = nullptr;
        for (auto* child : node->children) {
            if (HtmlParser::isInlineNode(child)) {
                if (!iRow) {
                    iRow = new Box(Axis::ROW);
                    iRow->setFlexWrap(true); iRow->setRowGap(10);
                    iRow->setAlignItems(AlignItems::FLEX_START);
                    if (ist.textAlign) applyTextAlign(iRow, *ist.textAlign);
                    cont->addView(iRow);
                }
                renderInline(child, iRow, baseFontSize,
                    currentTextColor ? *currentTextColor : defaultTextColor);
            } else {
                iRow = nullptr;
                buildHtmlViews(child, cont, baseFontSize,
                               currentTextColor, defaultTextColor, accentColor);
            }
        }

        std::string stTextFinal = node->attributes.count("style") ? node->attributes.at("style") : "";
        if (stTextFinal.find("border-bottom") != std::string::npos && ist.borderColor && ist.borderWidth) {
             Box* divider = new Box(Axis::ROW);
             divider->setHeight(*ist.borderWidth);
             divider->setBackgroundColor(*ist.borderColor);
             cont->addView(divider);
        }
    }

    baseFontSize     = oldSize;
    currentTextColor = oldColor;
}

} // namespace brls
