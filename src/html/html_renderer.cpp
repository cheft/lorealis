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

// Minimal internal HTML node structure
struct MiniNode {
    std::string tag;
    std::string text;
    std::map<std::string, std::string> attributes;
    std::vector<MiniNode*> children;
    bool isText = false;

    ~MiniNode() {
        for (auto child : children) delete child;
    }
};

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

// Simple state-machine HTML parser
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
            i = end + 1;
            
            if (tagContent.empty()) continue;
            
            if (tagContent[0] == '/') { // Closing tag
                if (stack.size() > 1) stack.pop();
            } else { // Opening tag
                bool selfClosing = (tagContent.back() == '/');
                if (selfClosing) tagContent.pop_back();
                
                std::stringstream ss(tagContent);
                std::string tagName;
                ss >> tagName;
                
                MiniNode* node = new MiniNode();
                node->tag = tagName;
                std::transform(node->tag.begin(), node->tag.end(), node->tag.begin(), ::tolower);
                
                // Extract attributes (primitive)
                std::string attr;
                while (ss >> attr) {
                    size_t eq = attr.find('=');
                    if (eq != std::string::npos) {
                        std::string key = attr.substr(0, eq);
                        std::string val = attr.substr(eq + 1);
                        if (val.size() >= 2 && (val[0] == '"' || val[0] == '\''))
                            val = val.substr(1, val.size() - 2);
                        node->attributes[key] = val;
                    }
                }
                
                stack.top()->children.push_back(node);
                if (!selfClosing && tagName != "br" && tagName != "img" && tagName != "hr") {
                    stack.push(node);
                }
            }
        } else {
            size_t next = html.find('<', i);
            std::string text = html.substr(i, (next == std::string::npos) ? std::string::npos : next - i);
            i = (next == std::string::npos) ? html.length() : next;
            
            // Trim and check if empty
            if (text.find_first_not_of(" \t\n\r") != std::string::npos) {
                MiniNode* node = new MiniNode();
                node->isText = true;
                node->text = text;
                stack.top()->children.push_back(node);
            }
        }
    }
    
    return root;
}

// Helper to parse CSS color hex
static std::optional<NVGcolor> parseColor(std::string str) {
    if (str.empty()) return std::nullopt;
    if (str[0] == '#') {
        if (str.length() == 7) {
            int r, g, b;
            sscanf(str.c_str(), "#%02x%02x%02x", &r, &g, &b);
            return nvgRGB((unsigned char)r, (unsigned char)g, (unsigned char)b);
        }
    }
    // Simple named colors
    if (str == "red") return nvgRGB(255, 0, 0);
    if (str == "blue") return nvgRGB(0, 0, 255);
    if (str == "green") return nvgRGB(0, 255, 0);
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
        key.erase(0, key.find_first_not_of(" \t\n\r"));
        key.erase(key.find_last_not_of(" \t\n\r") + 1);
        val.erase(0, val.find_first_not_of(" \t\n\r"));
        val.erase(val.find_last_not_of(" \t\n\r") + 1);

        if (key == "color") style.color = parseColor(val);
        else if (key == "font-size") style.fontSize = std::stof(val);
        else if (key == "margin-top") style.marginTop = std::stof(val);
        else if (key == "margin-bottom") style.marginBottom = std::stof(val);
    }
    return style;
}

NVGcolor HtmlRenderer::getThemeColor(const std::string& key) {
    return Application::getTheme().getColor(key);
}

void HtmlRenderer::applyStyle(View* view, const CssStyle& style) {
    if (style.marginTop) view->setMarginTop(*style.marginTop);
    if (style.marginBottom) view->setMarginBottom(*style.marginBottom);
    
    if (auto* label = dynamic_cast<Label*>(view)) {
        if (style.color) label->setTextColor(*style.color);
        if (style.fontSize) label->setFontSize(*style.fontSize);
    }
}

static bool isInlineNode(MiniNode* node) {
    if (node->isText) return true;
    static const std::vector<std::string> inlineTags = {
        "strong", "b", "i", "em", "span", "a", "u", "code", "font", "small", "big"
    };
    return std::find(inlineTags.begin(), inlineTags.end(), node->tag) != inlineTags.end();
}

void HtmlRenderer::renderString(const std::string& html) {
    clearViews();
    
    MiniNode* root = parseHTMLInternal(html);
    
    NVGcolor defaultTextColor = getThemeColor("brls/text");
    NVGcolor accentColor = getThemeColor("brls/accent");
    
    std::function<void(MiniNode*, Box*)> buildViews = [&](MiniNode* node, Box* parent) {
        if (node->isText) {
            Label* label = new Label();
            label->setText(node->text);
            label->setFontSize(baseFontSize);
            label->setTextColor(customTextColor ? *customTextColor : defaultTextColor);
            parent->addView(label);
            return;
        }

        float oldFontSize = baseFontSize;
        std::optional<NVGcolor> oldCustomColor = customTextColor;
        Box* currentContainer = parent;
        View* lastCreatedView = nullptr;
        bool skipChildren = false;

        CssStyle inlineStyle = parseInlineStyle(node->attributes["style"]);

        if (node->tag == "h1") {
            baseFontSize = 48.0f;
            Label* header = new Label();
            header->setMarginBottom(8);
            header->setMarginTop(5);
            lastCreatedView = header;
        }
        else if (node->tag == "h2") {
            baseFontSize = 40.0f;
            Label* header = new Label();
            header->setMarginBottom(6);
            header->setMarginTop(4);
            lastCreatedView = header;
        }
        else if (node->tag == "h3") {
            baseFontSize = 32.0f;
            Label* header = new Label();
            header->setMarginBottom(4);
            lastCreatedView = header;
        }
        else if (node->tag == "p") {
            baseFontSize = 26.0f;
            Box* pBox = new Box(Axis::COLUMN);
            pBox->setMarginBottom(10);
            currentContainer = pBox;
            parent->addView(pBox);
            lastCreatedView = pBox;
        }
        else if (node->tag == "strong" || node->tag == "b") {
            baseFontSize = oldFontSize * 1.1f; // Slight increase for "bold" look
            // No new box, just recurses into children which will be added to the current row-box
        }
        else if (node->tag == "i" || node->tag == "em") {
            // Placeholder for italic if supported, or just recursive
        }
        else if (node->tag == "ul" || node->tag == "ol") {
            Box* listContainer = new Box(Axis::COLUMN);
            listContainer->setPaddingLeft(30);
            listContainer->setMarginBottom(15);
            parent->addView(listContainer);
            currentContainer = listContainer;
            lastCreatedView = listContainer;
        }
        else if (node->tag == "li") {
            Box* row = new Box(Axis::ROW);
            row->setMarginBottom(5);
            Label* bullet = new Label();
            bullet->setText(" • ");
            bullet->setFontSize(baseFontSize);
            bullet->setTextColor(accentColor);
            row->addView(bullet);
            currentContainer = row;
            parent->addView(row);
            lastCreatedView = row;
        }
        else if (node->tag == "img") {
            std::string src = node->attributes["src"];
            if (!src.empty()) {
                Image* image = new Image();
                // Set placeholder first
                image->setImageFromRes("img/game_bg.jpg");
                
                // Load async if it's a URL
                if (src.find("http") == 0) {
                    image->setImageAsync([src](std::function<void(const std::string&, size_t length)> callback) {
                        SimpleHTTPClient::downloadImage(src, [callback](bool success, const std::string& data) {
                            if (success) {
                                callback(data, data.size());
                            }
                        });
                    });
                } else {
                    image->setImageFromFile(src);
                }
                
                image->setHeight(300);
                image->setCornerRadius(10);
                image->setMarginBottom(10);
                parent->addView(image);
                lastCreatedView = image;
            }
            skipChildren = true;
        }
        else if (node->tag == "a") {
            std::string href = node->attributes["href"];
            Label* link = new Label();
            link->setTextColor(accentColor);
            link->setFocusable(true);
            
            std::string linkText = "";
            std::function<void(MiniNode*)> collectText = [&](MiniNode* n) {
                if (n->isText) linkText += n->text;
                for (auto c : n->children) collectText(c);
            };
            for (auto child : node->children) collectText(child);
            link->setText(linkText);
            
            if (!href.empty()) {
                link->registerClickAction([href](View* v) {
                    Application::getPlatform()->openBrowser(href);
                    return true;
                });
            }
            
            parent->addView(link);
            lastCreatedView = link;
            skipChildren = true;
        }
        else if (node->tag == "br") {
            Box* spacer = new Box();
            spacer->setHeight(5);
            parent->addView(spacer);
            lastCreatedView = spacer;
            skipChildren = true;
        }
        else if (node->tag == "div") {
             Box* dBox = new Box(Axis::COLUMN);
             parent->addView(dBox);
             currentContainer = dBox;
             lastCreatedView = dBox;
        }
        else if (node->tag == "blockquote") {
            Box* qBox = new Box(Axis::COLUMN);
            qBox->setPaddingLeft(15);
            qBox->setPaddingTop(4);
            qBox->setPaddingBottom(4);
            qBox->setBackgroundColor(nvgRGBA(128, 128, 128, 25));
            qBox->setMarginBottom(12);
            qBox->setMarginTop(4);
            currentContainer = qBox;
            parent->addView(qBox);
            lastCreatedView = qBox;
        }

        if (lastCreatedView) applyStyle(lastCreatedView, inlineStyle);
        if (inlineStyle.color) customTextColor = inlineStyle.color;
        if (inlineStyle.fontSize) baseFontSize = *inlineStyle.fontSize;

        if (!skipChildren) {
            Box* inlineWrapper = nullptr;
            for (auto child : node->children) {
                if (isInlineNode(child)) {
                    if (!inlineWrapper) {
                        inlineWrapper = new Box(Axis::ROW);
                        inlineWrapper->setAlignItems(AlignItems::CENTER);
                        currentContainer->addView(inlineWrapper);
                    }
                    buildViews(child, inlineWrapper);
                } else {
                    inlineWrapper = nullptr;
                    buildViews(child, currentContainer);
                }
            }
        }

        baseFontSize = oldFontSize;
        customTextColor = oldCustomColor;
    };

    buildViews(root, this);
    delete root;
}

} // namespace brls
