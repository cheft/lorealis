#pragma once

#include <string>

namespace html {

std::string markdownToHtml(const std::string& md);
std::string rssToHtml(const std::string& xml);
std::string mailToHtml(const std::string& eml);

} // namespace html
