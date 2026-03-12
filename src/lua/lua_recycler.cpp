#include "lua_manager.hpp"
#include "lua_bindings.hpp"

// Helper class to expose protected inflateFromXMLRes and prepareForReuse callback
class LuaRecyclerCell : public brls::RecyclerCell {
public:
    PrepareForReuseCallback prepareCallback;
    
    static LuaRecyclerCell* create() {
        return new LuaRecyclerCell();
    }
    
    void loadXML(const std::string& path) {
        this->inflateFromXMLRes(path);
    }
    
    void prepareForReuse() override {
        brls::RecyclerCell::prepareForReuse();
        if (prepareCallback) {
            prepareCallback();
        }
    }
    
    void setPrepareForReuseCallback(PrepareForReuseCallback cb) {
        prepareCallback = cb;
    }
};

class LuaRecyclerDataSource : public brls::RecyclerDataSource {
public:
    sol::table dataSourceTable;
    LuaRecyclerDataSource(sol::table table) : dataSourceTable(table) {}

    int numberOfRows(brls::RecyclerFrame* recycler, int section) override {
        sol::protected_function func = dataSourceTable["numberOfRows"];
        if (func.valid()) {
            auto res = func(recycler, section);
            if (res.valid()) return res;
            sol::error err = res;
            brls::Logger::error("Lua error in numberOfRows: {}", err.what());
        }
        return 0;
    }

    int numberOfSections(brls::RecyclerFrame* recycler) override {
        sol::protected_function func = dataSourceTable["numberOfSections"];
        if (func.valid()) {
            auto res = func(recycler);
            if (res.valid()) return res;
            sol::error err = res;
            brls::Logger::error("Lua error in numberOfSections: {}", err.what());
        }
        return 1;
    }

    std::string titleForHeader(brls::RecyclerFrame* recycler, int section) override {
        sol::protected_function func = dataSourceTable["titleForHeader"];
        if (func.valid()) {
            auto res = func(recycler, section);
            if (res.valid() && res.get_type() == sol::type::string) return res.get<std::string>();
            sol::error err = res;
            brls::Logger::error("Lua error in titleForHeader: {}", err.what());
        }
        return "";
    }

    brls::RecyclerCell* cellForRow(brls::RecyclerFrame* recycler, brls::IndexPath indexPath) override {
        sol::protected_function func = dataSourceTable["cellForRow"];
        if (func.valid()) {
            auto res = func(recycler, (int)indexPath.section, indexPath.row);
            if (res.valid()) {
                sol::object ret = res;
                if (ret.is<brls::RecyclerCell*>()) return ret.as<brls::RecyclerCell*>();
                if (ret.is<brls::Box*>()) return (brls::RecyclerCell*)ret.as<brls::Box*>();
                brls::Logger::error("Lua error in cellForRow: Return type is not a Box or RecyclerCell");
            } else { 
                sol::error err = res;
                brls::Logger::error("Lua error in cellForRow: {}", err.what()); 
            }
        }
        return nullptr;
    }

    float heightForRow(brls::RecyclerFrame* recycler, brls::IndexPath indexPath) override {
        sol::protected_function func = dataSourceTable["heightForRow"];
        if (func.valid()) {
            auto res = func(recycler, (int)indexPath.section, indexPath.row);
            if (res.valid()) return res;
            sol::error err = res;
            brls::Logger::error("Lua error in heightForRow: {}", err.what());
        }
        return -1;
    }

    void didSelectRowAt(brls::RecyclerFrame* recycler, brls::IndexPath indexPath) override {
        sol::protected_function func = dataSourceTable["didSelectRowAt"];
        if (func.valid()) {
            auto res = func(recycler, (int)indexPath.section, indexPath.row);
            if (!res.valid()) {
                sol::error err = res;
                brls::Logger::error("Lua error in didSelectRowAt: {}", err.what());
            }
        }
    }
};

void LuaManager::registerRecyclerBindings(sol::table& brls_ns) {
    // Dropdown
    brls_ns["Dropdown"] = lua.create_table();
    brls_ns["Dropdown"]["new"] = [](const std::string& title, sol::table values, sol::protected_function cb, int selected) -> brls::Dropdown* {
        std::vector<std::string> opts;
        for (size_t i = 1; i <= values.size(); ++i) { 
            sol::object val = values[i];
            if (val.is<std::string>()) {
                opts.push_back(val.as<std::string>());
            }
        }
        brls::Logger::info("Dropdown::new: '{}' with {} options, selected={}", title, opts.size(), selected);
        return new brls::Dropdown(title, opts, [cb](int sel) { 
            if (cb.valid()) { 
                auto res = cb(sel);
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in Dropdown: {}", err.what()); }
            }
        }, selected);
    };

    auto dropdown_ut = brls_ns.new_usertype<brls::Dropdown>("DropdownInst",
        sol::no_constructor,
        sol::base_classes, sol::bases<brls::Box>()
    );

    // Recycler - Register base RecyclerCell first
    auto recycler_cell_ut = brls_ns.new_usertype<brls::RecyclerCell>("RecyclerCell",
        sol::no_constructor,
        sol::base_classes, sol::bases<brls::Box, brls::View>()
    );
    
    // Also register LuaRecyclerCell with the callback method
    auto lua_recycler_cell_ut = brls_ns.new_usertype<LuaRecyclerCell>("LuaRecyclerCell",
        sol::no_constructor,
        sol::base_classes, sol::bases<brls::RecyclerCell, brls::Box, brls::View>()
    );
    lua_recycler_cell_ut.set_function("setPrepareForReuseCallback", [](LuaRecyclerCell& self, sol::protected_function func) {
        self.setPrepareForReuseCallback([func]() {
            if (func.valid()) {
                auto res = func();
                if (!res.valid()) {
                    sol::error err = res;
                    brls::Logger::error("Lua error in prepareForReuse: {}", err.what());
                }
            }
        });
    });

    // Bind static create method on the table, not the usertype
    brls_ns["RecyclerCell"]["create"] = []() -> brls::RecyclerCell* {
        return LuaRecyclerCell::create();
    };
    // Create RecyclerCell from XML using helper class
    brls_ns["RecyclerCell"]["createFromXML"] = [](const std::string& path) -> LuaRecyclerCell* {
        auto* cell = LuaRecyclerCell::create();
        if (cell) {
            cell->loadXML(path);
        }
        return cell;
    };

    auto recycler_header_ut = brls_ns.new_usertype<brls::RecyclerHeader>("RecyclerHeader",
        sol::no_constructor,
        sol::base_classes, sol::bases<brls::RecyclerCell, brls::Box, brls::View>()
    );
    brls_ns["RecyclerHeader"]["create"] = []() -> brls::RecyclerHeader* {
        return brls::RecyclerHeader::create();
    };
    recycler_header_ut["setTitle"] = &brls::RecyclerHeader::setTitle;
    recycler_header_ut["setSubtitle"] = &brls::RecyclerHeader::setSubtitle;

    auto recycler_ut = brls_ns.new_usertype<brls::RecyclerFrame>("RecyclerFrame",
        sol::no_constructor,
        sol::base_classes, sol::bases<brls::View>()
    );
    recycler_ut.set_function("setEstimatedRowHeight", [](brls::RecyclerFrame& self, float h) { self.estimatedRowHeight = h; });
    recycler_ut.set_function("setDataSource", [](brls::RecyclerFrame& self, sol::table table) {
        self.setDataSource(new LuaRecyclerDataSource(table));
    });
    recycler_ut.set_function("registerCell", [](brls::RecyclerFrame& self, const std::string& identifier, sol::protected_function factory) {
        self.registerCell(identifier, [factory, identifier]() -> brls::RecyclerCell* {
            if (!factory.valid()) return nullptr;
            auto res = factory();
            if (res.valid()) {
                sol::object ret = res;
                if (ret.is<brls::RecyclerCell*>()) return ret.as<brls::RecyclerCell*>();
                if (ret.is<brls::Box*>()) {
                    auto* cell = dynamic_cast<brls::RecyclerCell*>(ret.as<brls::Box*>());
                    if (cell) return cell;
                    brls::Logger::error("Lua error in registerCell '{}': Box is not a RecyclerCell", identifier);
                }
            } else {
                sol::error err = res;
                brls::Logger::error("Lua error in registerCell '{}' factory: {}", identifier, err.what());
            }
            return nullptr;
        });
    });
    recycler_ut.set_function("dequeueReusableCell", [](brls::RecyclerFrame& self, const std::string& identifier) {
        // Cast to LuaRecyclerCell since that's what we always create
        brls::RecyclerCell* cell = self.dequeueReusableCell(identifier);
        if (cell) {
            // All our cells are LuaRecyclerCell, so this cast is safe
            return LuaManager::getInstance().pushView(static_cast<LuaRecyclerCell*>(cell));
        }
        return LuaManager::getInstance().pushView(static_cast<LuaRecyclerCell*>(nullptr));
    });
    recycler_ut["reloadData"] = &brls::RecyclerFrame::reloadData;
}
