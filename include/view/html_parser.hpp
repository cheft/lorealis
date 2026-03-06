#pragma once

#include <string>
#include <map>
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

class HtmlParser {
public:
    static MiniNode* parseHTML(const std::string& html);
    static std::string collectText(MiniNode* node);
    static std::string unescapeHtml(const std::string& s);
    static bool isInlineTag(const std::string& t);
    static bool isInlineNode(MiniNode* n);
    static std::string strTrim(const std::string& s);
    static std::string toLower(std::string s);
};

} // namespace brls
