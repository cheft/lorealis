#include "view/html_parser.hpp"
#include <stack>
#include <sstream>
#include <set>
#include <algorithm>
#include <cctype>

namespace brls {

MiniNode::~MiniNode() {
    for (auto* c : children) {
        delete c;
    }
}

std::string HtmlParser::strTrim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return {};
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

std::string HtmlParser::toLower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), ::tolower);
    return s;
}

std::string HtmlParser::unescapeHtml(const std::string& s) {
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

std::string HtmlParser::collectText(MiniNode* n) {
    if (n->isText) return n->text;
    std::string r;
    for (auto* c : n->children) r += collectText(c);
    return r;
}

bool HtmlParser::isInlineTag(const std::string& t) {
    static const std::set<std::string> S = {
        "strong","b","i","em","span","a","u","code","font",
        "small","big","del","s","ins","mark","sup","sub","br"
    };
    return S.count(t) > 0;
}

bool HtmlParser::isInlineNode(MiniNode* n) {
    return n->isText || isInlineTag(n->tag);
}

MiniNode* HtmlParser::parseHTML(const std::string& html) {
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
                // Filter out content inside script and style tags
                bool skipContent = false;
                std::stack<MiniNode*> filterStack = stk;
                while (!filterStack.empty()) {
                    std::string t = filterStack.top()->tag;
                    if (t == "script" || t == "style") { skipContent = true; break; }
                    filterStack.pop();
                }

                if (!skipContent) {
                    std::string norm;
                    bool lastWasSpace = false;
                    for (char c : raw) {
                        if (isspace((unsigned char)c)) {
                            if (!lastWasSpace) { norm += ' '; lastWasSpace = true; }
                        } else { norm += c; lastWasSpace = false; }
                    }
                    if (norm == " " && topNode()->children.empty()) { /* skip leading space */ }
                    else if (!norm.empty()) {
                        MiniNode* tn = new MiniNode(); tn->isText = true; tn->text = unescapeHtml(norm);
                        topNode()->children.push_back(tn);
                    }
                }
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

} // namespace brls
