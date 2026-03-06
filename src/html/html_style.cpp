#include "view/html_style.hpp"
#include <sstream>
#include <vector>
#include <algorithm>
#include <stdio.h>

namespace brls {

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

std::optional<NVGcolor> HtmlStyle::parseColor(const std::string& raw) {
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

float HtmlStyle::parseSize(const std::string& str, float base) {
    std::string s = strTrim(str);
    if (s.empty()) return 0.0f;
    try {
        if (!s.empty() && s.back() == '%') {
            float val = std::stof(s.substr(0, s.size() - 1));
            return (val / 100.0f) * base;
        }
        return std::stof(s);
    } catch (...) {
        return 0.0f;
    }
}

// Helper: parse a CSS length value (e.g. "12px", "1.5em") → float dp
static float parsePx(const std::string& v) {
    return HtmlStyle::parseSize(v);
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

CssStyle HtmlStyle::parseInlineStyle(const std::string& css) {
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
            // Sometimes background CSS has url(...) etc, we just try to extract color
            if (v.find("url") == std::string::npos && v.find("gradient") == std::string::npos) {
                 st.backgroundColor = parseColor(v);
            }
            // Better fallback: search for hex code
            else {
                 size_t hexPos = v.find('#');
                 if (hexPos != std::string::npos) {
                     std::string hexStr;
                     while(hexPos < v.size() && (isalnum(v[hexPos]) || v[hexPos] == '#')) {
                         hexStr += v[hexPos++];
                     }
                     st.backgroundColor = parseColor(hexStr);
                 }
            }
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
        else if (k == "width") {
            if (!v.empty() && v.back() == '%') {
                try { st.widthPercentage = std::stof(v.substr(0, v.size() - 1)); } catch (...) {}
            } else {
                try { st.width = std::stof(v); } catch (...) {}
            }
        }
        else if (k == "height") {
            if (!v.empty() && v.back() == '%') {
                try { st.heightPercentage = std::stof(v.substr(0, v.size() - 1)); } catch (...) {}
            } else {
                try { st.height = std::stof(v); } catch (...) {}
            }
        }
        else if (k == "overflow") {
            st.overflowHidden = (toLower(v) == "hidden");
        }
        else if (k == "border" || k == "border-bottom" || k == "border-top") {
            // e.g. "1px solid #dadce0"
            auto col = parseColor(v.substr(v.rfind(' ') + 1));
            if (col) st.borderColor = col;
            try { st.borderWidth = std::stof(v); } catch (...) { st.borderWidth = 1.f; }
        }
    }
    return st;
}

} // namespace brls
