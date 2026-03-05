#pragma once

#include "view/html_renderer.hpp"

namespace brls {

class MarkdownRenderer : public HtmlRenderer {
public:
    MarkdownRenderer();
    ~MarkdownRenderer();

    static MarkdownRenderer* create();

    void renderMarkdown(const std::string& md);
    void renderMarkdownFile(const std::string& path);

private:
    std::string markdownToHtml(const std::string& md);
};

} // namespace brls
