#include "html/format_converters.hpp"
#include <pugixml.hpp>
#include <iostream>
#include <sstream>
#include <vector>
#include <regex>

namespace html {

// Very basic internal Markdown subset renderer
std::string markdownToHtml(const std::string& md) {
    std::stringstream ss;
    ss << "<html><body>";
    
    std::stringstream input(md);
    std::string line;
    bool inList = false;

    while (std::getline(input, line)) {
        if (line.empty()) {
            if (inList) { ss << "</ul>"; inList = false; }
            continue;
        }

        // Headers
        if (line.substr(0, 3) == "###") ss << "<h3>" << line.substr(3) << "</h3>";
        else if (line.substr(0, 2) == "##") ss << "<h2>" << line.substr(2) << "</h2>";
        else if (line.substr(0, 1) == "#") ss << "<h1>" << line.substr(1) << "</h1>";
        // List item
        else if (line.substr(0, 2) == "- " || line.substr(0, 2) == "* ") {
            if (!inList) { ss << "<ul>"; inList = true; }
            ss << "<li>" << line.substr(2) << "</li>";
        }
        // Paragraph
        else {
            if (inList) { ss << "</ul>"; inList = false; }
            std::string processed = line;
            // Simple bold/italic regex replacement
            processed = std::regex_replace(processed, std::regex("\\*\\*(.*?)\\*\\*"), "<strong>$1</strong>");
            processed = std::regex_replace(processed, std::regex("\\*(.*?)\\*"), "<em>$1</em>");
            ss << "<p>" << processed << "</p>";
        }
    }
    
    if (inList) ss << "</ul>";
    ss << "</body></html>";
    return ss.str();
}

std::string rssToHtml(const std::string& xml) {
    pugi::xml_document doc;
    pugi::xml_parse_result result = doc.load_string(xml.c_str());
    if (!result) return "<html><body>Error parsing RSS</body></html>";

    std::stringstream ss;
    ss << "<html><body>";

    pugi::xml_node feed = doc.child("feed");
    if (feed) {
        ss << "<h1>" << feed.child_value("title") << "</h1>";
        for (pugi::xml_node entry = feed.child("entry"); entry; entry = entry.next_sibling("entry")) {
            ss << "<h2>" << entry.child_value("title") << "</h2>";
            ss << "<div>" << entry.child_value("content") << "</div>";
            ss << "<hr/>";
        }
    } else {
        pugi::xml_node channel = doc.child("rss").child("channel");
        if (channel) {
            ss << "<h1>" << channel.child_value("title") << "</h1>";
            for (pugi::xml_node item = channel.child("item"); item; item = item.next_sibling("item")) {
                ss << "<h2>" << item.child_value("title") << "</h2>";
                ss << "<div>" << item.child_value("description") << "</div>";
                ss << "<hr/>";
            }
        }
    }

    ss << "</body></html>";
    return ss.str();
}

std::string mailToHtml(const std::string& eml) {
    size_t pos = eml.find("\r\n\r\n");
    if (pos == std::string::npos) pos = eml.find("\n\n");
    
    std::string body = (pos != std::string::npos) ? eml.substr(pos + 2) : eml;
    if (body.find("<html") != std::string::npos || body.find("<body") != std::string::npos) {
        return body;
    }
    return "<html><body><p>" + body + "</p></body></html>";
}

} // namespace html
