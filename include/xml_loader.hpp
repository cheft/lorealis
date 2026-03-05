#pragma once

#include <borealis.hpp>
#include <string>

class XMLLoader {
public:
    // Load a view from XML and bind its elements to Lua
    static brls::View* load(const std::string& path);

    // Load a view from an XML resource path (relative to resources dir) and bind to Lua
    static brls::View* loadResource(const std::string& name);
};
