#include "lua_manager.hpp"
#include <borealis/views/cells/cell_input.hpp>

void LuaManager::registerCellBindings(sol::table& brls_ns) {
    // 1. Base Type: DetailCell (Register this FIRST)
    // We use lambdas for title and detail to resolve BRLS_BIND types correctly in Lua
    auto detail_cell_ut = brls_ns.new_usertype<brls::DetailCell>("DetailCell",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::RecyclerCell, brls::Box, brls::View>()
    );
    detail_cell_ut["setDetailText"] = &brls::DetailCell::setDetailText;
    detail_cell_ut["setText"] = &brls::DetailCell::setText;
    detail_cell_ut["setTitle"] = &brls::DetailCell::setText;
    detail_cell_ut["title"] = sol::property([](brls::DetailCell& self) { return (brls::Label*)self.title; });
    detail_cell_ut["detail"] = sol::property([](brls::DetailCell& self) { return (brls::Label*)self.detail; });
    detail_cell_ut["onClick"] = [](brls::DetailCell& self, sol::protected_function func) {
        self.registerClickAction([func](brls::View* v) -> bool {
            auto result = func(v);
            if (!result.valid()) { sol::error err = result; brls::Logger::error("Lua error in DetailCell click: {}", err.what()); return true; }
            if (result.get_type() != sol::type::boolean) return true;
            return result.get<bool>();
        });
    };

    // 2. BooleanCell
    auto boolean_cell_ut = brls_ns.new_usertype<brls::BooleanCell>("BooleanCell",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::DetailCell, brls::RecyclerCell, brls::Box, brls::View>()
    );
    boolean_cell_ut["title"] = sol::property([](brls::BooleanCell& self) { return (brls::Label*)self.title; });
    boolean_cell_ut["detail"] = sol::property([](brls::BooleanCell& self) { return (brls::Label*)self.detail; });
    boolean_cell_ut["init"] = [](brls::BooleanCell& self, const std::string& title, bool value, sol::protected_function cb) {
        self.init(title, value, [cb](bool v) { 
            if (cb.valid()) {
                auto res = cb(v);
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in boolean cell: {}", err.what()); }
            }
        });
    };
    boolean_cell_ut["onClick"] = [](brls::BooleanCell& self, sol::protected_function func) {
        self.registerClickAction([func](brls::View* v) -> bool {
            auto result = func(v);
            if (!result.valid()) { sol::error err = result; brls::Logger::error("Lua error in boolean cell click: {}", err.what()); return true; }
            if (result.get_type() != sol::type::boolean) return true;
            return result.get<bool>();
        });
    };

    // 3. SliderCell
    auto slider_cell_ut = brls_ns.new_usertype<brls::SliderCell>("SliderCell",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::DetailCell, brls::RecyclerCell, brls::Box, brls::View>()
    );
    slider_cell_ut["title"] = sol::property([](brls::SliderCell& self) { return (brls::Label*)self.title; });
    slider_cell_ut["detail"] = sol::property([](brls::SliderCell& self) { return (brls::Label*)self.detail; });
    slider_cell_ut["init"] = [](brls::SliderCell& self, const std::string& title, float value, sol::protected_function cb) {
        self.init(title, value, [cb](float v) { 
            if (cb.valid()) {
                auto res = cb(v);
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in slider cell: {}", err.what()); }
            }
        });
    };
    slider_cell_ut["getSlider"] = [](brls::SliderCell& self) { return self.slider; };

    // 4. RadioCell
    auto radio_cell_ut = brls_ns.new_usertype<brls::RadioCell>("RadioCell",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::RecyclerCell, brls::Box, brls::View>()
    );
    radio_cell_ut["title"] = sol::property([](brls::RadioCell& self) { return (brls::Label*)self.title; });
    radio_cell_ut["setSelected"] = &brls::RadioCell::setSelected;
    radio_cell_ut["onClick"] = [](brls::RadioCell& self, sol::protected_function func) {
        self.registerClickAction([func](brls::View* v) -> bool {
            auto result = func(v);
            if (!result.valid()) { sol::error err = result; brls::Logger::error("Lua error in radio cell click: {}", err.what()); return true; }
            if (result.get_type() != sol::type::boolean) return true;
            return result.get<bool>();
        });
    };

    // 5. SelectorCell
    auto selector_cell_ut = brls_ns.new_usertype<brls::SelectorCell>("SelectorCell",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::DetailCell, brls::RecyclerCell, brls::Box, brls::View>()
    );
    selector_cell_ut["title"] = sol::property([](brls::SelectorCell& self) { return (brls::Label*)self.title; });
    selector_cell_ut["detail"] = sol::property([](brls::SelectorCell& self) { return (brls::Label*)self.detail; });
    selector_cell_ut["init"] = [](brls::SelectorCell& self, const std::string& title, sol::table options, int selected, sol::protected_function onHighlight, sol::protected_function onSelect) {
        std::vector<std::string> opts;
        for (size_t i = 1; ; ++i) { 
            sol::object val = options[i];
            if (val.is<std::string>()) {
                opts.push_back(val.as<std::string>());
            } else {
                break;
            }
        }
        
        self.init(title, opts, selected, 
            [onHighlight](int i) { 
                if (onHighlight.valid()) {
                    auto res = onHighlight(i);
                    if (!res.valid()) { sol::error err = res; brls::Logger::error("SelectorCell onHighlight error: {}", err.what()); }
                }
            }, 
            [onSelect](int i) { 
                if (onSelect.valid()) {
                    auto res = onSelect(i);
                    if (!res.valid()) { sol::error err = res; brls::Logger::error("SelectorCell onSelect error: {}", err.what()); }
                }
            });
    };

    // 6. InputCell
    auto input_cell_ut = brls_ns.new_usertype<brls::InputCell>("InputCell",
        sol::factories(
            []() { return new brls::InputCell(); }
        ),
        sol::base_classes, sol::bases<brls::DetailCell, brls::RecyclerCell, brls::Box, brls::View>()
    );
    input_cell_ut["title"] = sol::property([](brls::InputCell& self) { return (brls::Label*)self.title; });
    input_cell_ut["detail"] = sol::property([](brls::InputCell& self) { return (brls::Label*)self.detail; });
    input_cell_ut["init"] = [](brls::InputCell& self, const std::string& title, const std::string& value, sol::protected_function cb, const std::string& placeholder, const std::string& hint, sol::optional<int> maxInputLength) {
        self.init(title, value, [cb](std::string text) {
            if (cb.valid()) {
                auto res = cb(text);
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in InputCell: {}", err.what()); }
            }
        }, placeholder, hint, maxInputLength.value_or(32));
    };
    input_cell_ut["setValue"] = &brls::InputCell::setValue;
    input_cell_ut["getValue"] = &brls::InputCell::getValue;
    input_cell_ut["openKeyboard"] = [](brls::InputCell& self, sol::optional<int> maxInputLength) -> bool {
        // This simulates the behavior of clicking on the cell and returns whether IME opened successfully.
        return brls::Application::getImeManager()->openForText([&self](std::string text) {
            self.setValue(text);
        },
        ((brls::Label*)self.title)->getFullText(), self.getHint(), maxInputLength.value_or(256), self.getValue(), 0);
    };

    // 7. InputNumericCell
    auto input_numeric_cell_ut = brls_ns.new_usertype<brls::InputNumericCell>("InputNumericCell",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::DetailCell, brls::RecyclerCell, brls::Box, brls::View>()
    );
    input_numeric_cell_ut["title"] = sol::property([](brls::InputNumericCell& self) { return (brls::Label*)self.title; });
    input_numeric_cell_ut["detail"] = sol::property([](brls::InputNumericCell& self) { return (brls::Label*)self.detail; });
    input_numeric_cell_ut["init"] = [](brls::InputNumericCell& self, const std::string& title, long value, sol::protected_function cb, const std::string& hint) {
        self.init(title, value, [cb](long val) {
            if (cb.valid()) {
                auto res = cb(val);
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in InputNumericCell: {}", err.what()); }
            }
        }, hint);
    };

    // 8. Slider (Stand alone view)
    auto slider_ut = brls_ns.new_usertype<brls::Slider>("Slider",
        sol::no_construction(),
        sol::base_classes, sol::bases<brls::Box, brls::View>()
    );
    slider_ut["getProgress"] = &brls::Slider::getProgress;
    slider_ut["setProgress"] = &brls::Slider::setProgress;
    slider_ut["setStep"] = &brls::Slider::setStep;
    slider_ut["setPointerSize"] = &brls::Slider::setPointerSize;
    slider_ut["onProgressChange"] = [](brls::Slider& self, sol::protected_function func) {
        // Clear existing subscriptions to prevent accumulation on repeated calls
        self.getProgressEvent()->clear();
        self.getProgressEvent()->subscribe([func](float p) {
            if (func.valid()) {
                auto res = func(p);
                if (!res.valid()) { sol::error err = res; brls::Logger::error("Lua error in slider progress: {}", err.what()); }
            }
        });
    };
}
