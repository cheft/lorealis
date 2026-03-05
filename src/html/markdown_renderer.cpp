#include "view/markdown_renderer.hpp"
#include <borealis/core/logger.hpp>
#include <fstream>
#include <sstream>
#include <regex>
#include <string>
#include <algorithm>

namespace brls {

MarkdownRenderer::MarkdownRenderer() {}
MarkdownRenderer::~MarkdownRenderer() {}

MarkdownRenderer* MarkdownRenderer::create() {
    return new MarkdownRenderer();
}

void MarkdownRenderer::renderMarkdown(const std::string& md) {
    renderString(markdownToHtml(md));
}

void MarkdownRenderer::renderMarkdownFile(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        Logger::error("MarkdownRenderer: Could not open file {}", path);
        return;
    }
    std::stringstream buffer;
    buffer << file.rdbuf();
    renderMarkdown(buffer.str());
}

// ============================================================
// Helpers
// ============================================================
static std::string escapeHtml(const std::string& s) {
    std::string result;
    result.reserve(s.size());
    for (char c : s) {
        switch (c) {
            case '&':  result += "&amp;";  break;
            case '<':  result += "&lt;";   break;
            case '>':  result += "&gt;";   break;
            // Removed &quot; escaping to preserve raw JSON/code formatting
            default:   result += c;        break;
        }
    }
    return result;
}

static std::string trimStr(const std::string& s) {
    size_t start = s.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

// ============================================================
// Inline Markdown -> HTML
//   Processes: **bold**, *italic*, ***bold-italic***,
//              ~~strikethrough~~, `code`, [link](url), ![img](src)
// ============================================================
static std::string processInline(const std::string& text) {
    std::string out = text;

    // Images before links (same syntax)
    out = std::regex_replace(out, std::regex(R"(!\[([^\]]*)\]\(([^)]*)\))"),
        "<img src=\"$2\" alt=\"$1\"/>");

    // Links
    out = std::regex_replace(out, std::regex(R"(\[([^\]]+)\]\(([^)]+)\))"),
        "<a href=\"$2\">$1</a>");

    // Bold-italic (must come before bold/italic alone)
    out = std::regex_replace(out, std::regex(R"(\*\*\*(.+?)\*\*\*)"),
        "<strong><em>$1</em></strong>");
    out = std::regex_replace(out, std::regex(R"(\*\*(.+?)\*\*)"),
        "<strong>$1</strong>");
    out = std::regex_replace(out, std::regex(R"(\*(.+?)\*)"),
        "<em>$1</em>");

    // Underscores (same priority)
    out = std::regex_replace(out, std::regex(R"(___(.+?)___)"),
        "<strong><em>$1</em></strong>");
    out = std::regex_replace(out, std::regex(R"(__(.+?)__)"),
        "<strong>$1</strong>");
    out = std::regex_replace(out, std::regex(R"(_([^_\s][^_]*[^_\s]?)_)"),
        "<em>$1</em>");

    // Strikethrough
    out = std::regex_replace(out, std::regex(R"(~~(.+?)~~)"),
        "<del>$1</del>");

    // Inline code (last so it protects its content)
    out = std::regex_replace(out, std::regex(R"(`([^`]+)`)"),
        "<code>$1</code>");

    return out;
}

// ============================================================
// Table parsing helper
// ============================================================
static std::vector<std::string> splitTableRow(const std::string& line) {
    std::vector<std::string> cells;
    std::string row = line;
    // Strip leading/trailing pipe
    if (!row.empty() && row.front() == '|') row = row.substr(1);
    if (!row.empty() && row.back()  == '|') row.pop_back();
    std::stringstream ss(row);
    std::string cell;
    while (std::getline(ss, cell, '|')) {
        cells.push_back(trimStr(cell));
    }
    return cells;
}

static bool isTableSeparator(const std::string& line) {
    // e.g. |---|---|---|
    for (char c : line) {
        if (c != '|' && c != '-' && c != ':' && c != ' ' && c != '\t') return false;
    }
    return line.find('-') != std::string::npos;
}

// ============================================================
// Main converter: Markdown -> HTML
// ============================================================
std::string MarkdownRenderer::markdownToHtml(const std::string& md) {
    // Normalize line endings
    std::string src = md;
    src = std::regex_replace(src, std::regex("\r\n"), "\n");
    src = std::regex_replace(src, std::regex("\r"), "\n");

    std::vector<std::string> lines;
    std::stringstream ss(src);
    std::string line;
    while (std::getline(ss, line)) lines.push_back(line);

    std::string html;
    size_t i = 0;
    const size_t N = lines.size();

    // State
    bool inCodeBlock  = false;
    std::string codeBlockLang;
    std::string codeBlockContent;

    auto flushCodeBlock = [&]() {
        html += "<pre><code class=\"lang-" + escapeHtml(codeBlockLang) + "\">";
        html += escapeHtml(codeBlockContent);
        html += "</code></pre>\n";
        codeBlockContent.clear();
        codeBlockLang.clear();
        inCodeBlock = false;
    };

    while (i < N) {
        const std::string& raw = lines[i];
        std::string trimmed = trimStr(raw);

        // ── Fenced code block ──────────────────────────────────
        if (!inCodeBlock && trimmed.substr(0, 3) == "```") {
            codeBlockLang = trimStr(trimmed.substr(3));
            inCodeBlock = true;
            i++;
            continue;
        }
        if (inCodeBlock) {
            if (trimmed == "```") {
                flushCodeBlock();
            } else {
                codeBlockContent += raw + "\n";
            }
            i++;
            continue;
        }

        // ── Empty line ─────────────────────────────────────────
        if (trimmed.empty()) {
            i++;
            continue;
        }

        // ── ATX Headings (#) ───────────────────────────────────
        if (trimmed[0] == '#') {
            int level = 0;
            while (level < (int)trimmed.size() && trimmed[level] == '#') level++;
            if (level <= 6 && (size_t)level < trimmed.size() && trimmed[level] == ' ') {
                std::string content = processInline(trimStr(trimmed.substr(level + 1)));
                html += "<h" + std::to_string(level) + ">" + content + "</h" + std::to_string(level) + ">\n";
                i++;
                continue;
            }
        }

        // ── HR ─────────────────────────────────────────────────
        if (trimmed == "---" || trimmed == "***" || trimmed == "___" ||
            std::regex_match(trimmed, std::regex(R"([-*_]{3,})"))) {
            html += "<hr/>\n";
            i++;
            continue;
        }

        // ── Blockquote ─────────────────────────────────────────
        if (trimmed[0] == '>') {
            html += "<blockquote>\n";
            while (i < N) {
                std::string bqLine = trimStr(lines[i]);
                if (bqLine.empty()) { i++; break; }
                if (bqLine[0] != '>') break;
                std::string content = bqLine.size() > 1 ? trimStr(bqLine.substr(1)) : "";
                html += "<p>" + processInline(content) + "</p>\n";
                i++;
            }
            html += "</blockquote>\n";
            continue;
        }

        // ── Unordered List ─────────────────────────────────────
        if ((trimmed.size() >= 2) &&
            (trimmed[0] == '-' || trimmed[0] == '*' || trimmed[0] == '+') &&
            trimmed[1] == ' ') {
            html += "<ul>\n";
            int baseIndent = (int)(raw.find_first_not_of(" \t"));
            while (i < N) {
                std::string rawL   = lines[i];
                std::string trimL  = trimStr(rawL);
                if (trimL.empty()) { i++; break; }
                int indent = (int)(rawL.find_first_not_of(" \t"));
                // detect sub-list
                if (trimL[0] == '-' || trimL[0] == '*' || trimL[0] == '+') {
                    std::string itemText = trimStr(trimL.substr(2));
                    if (indent > baseIndent) {
                        // Sub-list: wrap in nested ul
                        html += "<li><ul>\n";
                        html += "<li>" + processInline(itemText) + "</li>\n";
                        // collect more sub-items
                        i++;
                        while (i < N) {
                            std::string rr = lines[i];
                            std::string tt = trimStr(rr);
                            int ind2 = (int)(rr.find_first_not_of(" \t"));
                            if (tt.empty() || ind2 <= baseIndent) break;
                            if ((tt[0] == '-' || tt[0] == '*' || tt[0] == '+') && tt[1] == ' ') {
                                html += "<li>" + processInline(trimStr(tt.substr(2))) + "</li>\n";
                            }
                            i++;
                        }
                        html += "</ul></li>\n";
                    } else {
                        html += "<li>" + processInline(itemText) + "</li>\n";
                        i++;
                    }
                } else if (std::isdigit(trimL[0])) {
                    break; // ordered list – stop
                } else {
                    break;
                }
            }
            html += "</ul>\n";
            continue;
        }

        // ── Ordered List ───────────────────────────────────────
        if (trimmed.size() >= 3 && std::isdigit(trimmed[0])) {
            size_t dot = trimmed.find('.');
            if (dot != std::string::npos && dot < 4 && trimmed.size() > dot + 1 && trimmed[dot+1] == ' ') {
                html += "<ol>\n";
                while (i < N) {
                    std::string trimL = trimStr(lines[i]);
                    if (trimL.empty()) { i++; break; }
                    size_t d = trimL.find('.');
                    if (d == std::string::npos || !std::isdigit(trimL[0])) break;
                    html += "<li>" + processInline(trimStr(trimL.substr(d + 2))) + "</li>\n";
                    i++;
                }
                html += "</ol>\n";
                continue;
            }
        }

        // ── Table ──────────────────────────────────────────────
        if (trimmed.find('|') != std::string::npos) {
            // Peek ahead to see if next line is separator
            bool isTable = (i + 1 < N && isTableSeparator(trimStr(lines[i+1])));
            if (isTable) {
                html += "<table>\n";
                // Header row
                auto headers = splitTableRow(trimmed);
                html += "<thead><tr>";
                for (auto& h : headers) html += "<th>" + processInline(h) + "</th>";
                html += "</tr></thead>\n";
                i += 2; // skip header + separator
                // Body rows
                html += "<tbody>\n";
                while (i < N) {
                    std::string rowLine = trimStr(lines[i]);
                    if (rowLine.empty() || rowLine.find('|') == std::string::npos) break;
                    auto cells = splitTableRow(rowLine);
                    html += "<tr>";
                    for (auto& c : cells) html += "<td>" + processInline(c) + "</td>";
                    html += "</tr>\n";
                    i++;
                }
                html += "</tbody></table>\n";
                continue;
            }
        }

        // ── Paragraph ──────────────────────────────────────────
        {
            // Collect consecutive non-empty, non-block lines
            std::string paraContent;
            while (i < N) {
                std::string trimL = trimStr(lines[i]);
                if (trimL.empty()) { i++; break; }
                // Stop at block-level markers
                if (trimL[0] == '#' || trimL[0] == '>' ||
                    trimL.substr(0,3) == "```" ||
                    ((trimL[0]=='-'||trimL[0]=='*'||trimL[0]=='+') && trimL.size()>1 && trimL[1]==' ') ||
                    (trimL.size()>=2 && std::isdigit(trimL[0]) && trimL.find('.')!=std::string::npos) ||
                    isTableSeparator(trimL) ||
                    trimL == "---" || trimL == "***" || trimL == "___")
                    break;
                if (!paraContent.empty()) paraContent += " ";
                paraContent += trimL;
                i++;
            }
            if (!paraContent.empty()) {
                html += "<p>" + processInline(paraContent) + "</p>\n";
            }
        }
    }

    // Flush unclosed code block
    if (inCodeBlock) flushCodeBlock();

    return html;
}

} // namespace brls
