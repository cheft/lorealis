#include "xml_loader.hpp"
#include "lua_manager.hpp"
#include <borealis/core/logger.hpp>
#include <typeinfo>

#include <borealis/views/image.hpp>
#include <borealis/views/label.hpp>
#include <borealis/core/application.hpp>
#include <borealis/core/style.hpp>
#include <borealis/core/theme.hpp>
#include <borealis/views/scrolling_frame.hpp>
#include <borealis/views/h_scrolling_frame.hpp>

// Shared recursive registration helper
static void registerViewsRecursive(brls::View* v) {
    if (!v) return;
    
    std::string id = v->getId();
    brls::Logger::debug("XMLLoader: Checking view '{}' (type: {})", id.empty() ? "[no id]" : id, typeid(*v).name());
    
    LuaManager::getInstance().registerView(v);
    
    // Check if the view is a container (Box and its subclasses like ScrollingFrame)
    if (auto* box = dynamic_cast<brls::Box*>(v)) {
        auto& children = box->getChildren();
        brls::Logger::debug("XMLLoader: View '{}' is a Box with {} children", id.empty() ? "[no id]" : id, children.size());
        for (brls::View* child : children) {
            registerViewsRecursive(child);
        }
    }
}

brls::View* XMLLoader::loadResource(const std::string& name) {
    brls::Logger::debug("XMLLoader: LoadResource {}", name);
    brls::View* view = brls::View::createFromXMLResource(name);
    if (!view) {
        brls::Logger::error("XMLLoader: Failed to load XML resource {}", name);
        return nullptr;
    }
    registerViewsRecursive(view);
    return view;
}

brls::View* XMLLoader::load(const std::string& path) {
    brls::Logger::debug("XMLLoader: Loading {}", path);
    // Standard Borealis XML creation
    brls::View* view = brls::View::createFromXMLFile(path);
    if (!view) {
        brls::Logger::error("XMLLoader: Failed to create view from {}", path);
        return nullptr;
    }

    // Recursively find all views with IDs and register them in Lua
    std::function<void(brls::View*)> registerRecursive = [&](brls::View* v) {
        if (!v) return;
        
        LuaManager::getInstance().registerView(v);
        
        if (auto* box = dynamic_cast<brls::Box*>(v)) {
            for (brls::View* child : box->getChildren()) {
                if (child) {
                    registerRecursive(child);
                }
            }
        }
    };

    brls::Logger::debug("XMLLoader: Starting recursive registration...");
    registerRecursive(view);
    brls::Logger::debug("XMLLoader: Registration complete.");
    return view;
}
