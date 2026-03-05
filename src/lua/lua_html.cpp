#include "lua_bindings.hpp"
#include "view/html_renderer.hpp"
#include "html/format_converters.hpp"
#include "lua_manager.hpp"

void LuaManager::registerHtmlBindings(sol::table& brls_ns) {
    // Bind HtmlRenderer
    brls_ns.new_usertype<brls::HtmlRenderer>("HtmlRenderer",
        sol::base_classes, sol::bases<brls::Box, brls::View>(),
        "new", sol::factories(&brls::HtmlRenderer::create),
        "renderString", &brls::HtmlRenderer::renderString,
        "renderFile", &brls::HtmlRenderer::renderFile,
        "setBaseFontSize", &brls::HtmlRenderer::setBaseFontSize
    );

    // Bind Format Converters
    auto html_ns = brls_ns["html"].get_or_create<sol::table>();
    html_ns["markdownToHtml"] = &html::markdownToHtml;
    html_ns["rssToHtml"] = &html::rssToHtml;
    html_ns["mailToHtml"] = &html::mailToHtml;
}

