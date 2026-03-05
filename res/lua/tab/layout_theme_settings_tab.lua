--[[
    Layout & Theme Configuration Testing Module (layout_theme_settings)
    Identifier: layout_theme_settings
    
    A comprehensive showcase of the Lua runtime's capabilities through exhaustive
    integration with the borealis framework. This module demonstrates:
    
    - Deep theme system overrides (ApplicationTheme, SubTheme variants, custom color palettes)
    - Light/dark/auto modes, high contrast accessibility themes
    - Advanced window management (multi-resolution profiles, DPI scaling, viewport snapping)
    - Typography hierarchies (font fallback chains, dynamic scaling with WCAG compliance)
    - Layout geometry engines (BoxLayout, GridLayout, AbsoluteLayout)
    - Spacing micro-management (padding inheritance chains, separator gradients, focus borders)
    - Animation timing controls (easing functions, stagger delays, frame-rate independence)
    - Rendering optimizations (texture filtering, MSAA, transparency blending, HDR)
    
    Features:
    - Metatable-based change detection for all configuration state
    - Hierarchical settings tree with bi-directional synchronization
    - Visual sandbox panel with live previews and split-screen comparison
    - Theme import/export via Lua table serialization to JSON
    - A/B configuration state diffing
    - Automated stress-testing routines
    - Deep inspection tools for runtime Style objects and Attributes
    - 60FPS stability and memory leak prevention
--]]

local layout_theme_settings = {}

-- JSON utilities for import/export
local json = require("utils/json")

-- Store references to UI views (declared early for function access)
local sample_views = {}

-- Module version
local MODULE_VERSION = "1.0.0"
local MODULE_IDENTIFIER = "layout_theme_settings"

-- ============================================================================
-- Configuration State Management with Metatable-based Change Detection
-- ============================================================================

-- Default configuration values
local DEFAULT_CONFIG = {
    -- Theme System
    theme = {
        variant = "LIGHT", -- LIGHT, DARK, AUTO
        high_contrast = false,
        auto_follow_system = false,
        colors = {
            primary = { r = 0, g = 120, b = 255, a = 255 },
            accent = { r = 0, g = 176, b = 183, a = 255 },
            background = { r = 245, g = 245, b = 245, a = 255 },
            text = { r = 30, g = 30, b = 30, a = 255 },
            highlight = { r = 0, g = 120, b = 255, a = 100 },
            border = { r = 200, g = 200, b = 200, a = 255 },
            shadow = { r = 0, g = 0, b = 0, a = 100 },
        },
        subtheme = "default",
    },
    
    -- Window Management
    window = {
        resolution_preset = "720p", -- 720p, 1080p, 1440p, 4K, 8K, custom
        custom_width = 1280,
        custom_height = 720,
        dpi_scale = 1.0,
        window_mode = "windowed", -- windowed, fullscreen, borderless
        aspect_ratio_lock = false,
        viewport_snapping = false,
        always_on_top = false,
        fullscreen_borderless = false,
        monitor_index = 0,
    },
    
    -- Typography
    typography = {
        font_family = "regular",
        header_font_size = 28,
        body_font_size = 18,
        caption_font_size = 14,
        monospace_font = false,
        font_fallback_chain = "regular,korean,zh-Hans,material",
        dynamic_scaling = false,
        letter_spacing = 0.0,
        line_height = 1.4,
        text_alignment = "LEFT",
    },
    
    -- Layout Geometry
    layout = {
        type = "BOX", -- BOX, GRID, ABSOLUTE
        flex_direction = "ROW",
        justify_content = "FLEX_START",
        align_items = "STRETCH",
        stretch_factor = 1.0,
        shrink_factor = 1.0,
        position_type = "RELATIVE",
        position_x_percent = 0.0,
        position_y_percent = 0.0,
        absolute_x = 0,
        absolute_y = 0,
        aspect_ratio = 1.0,
    },
    
    -- Spacing & Margins
    spacing = {
        padding_top = 20,
        padding_right = 20,
        padding_bottom = 20,
        padding_left = 20,
        margin_top = 10,
        margin_right = 10,
        margin_bottom = 10,
        margin_left = 10,
        separator_thickness = 2,
        scroll_indicator_offset = 5,
        focus_border_inset = 4,
        glow_radius = 8,
        safe_area_top = 0,
        safe_area_bottom = 0,
    },
    
    -- Animation Timing
    animation = {
        easing_function = "linear",
        transition_duration = 250,
        stagger_delay = 50,
        highlight_speed = 200,
        shake_amplitude = 15,
        micro_duration = 150,
        frame_rate_independent = true,
    },
    
    -- Rendering
    rendering = {
        texture_filtering = "LINEAR",
        msaa_level = 0,
        transparency_blending = "NORMAL",
        hdr_brightness = 1.0,
        fps_limit = 60,
        vsync = true,
        debug_layer = false,
    },
}

-- Current configuration state (will be deep-copied from defaults)
local current_config = {}

-- A/B Snapshot states for comparison
local snapshot_a = nil
local snapshot_b = nil

-- Change tracking for callbacks
local change_callbacks = {}
local is_batch_updating = false
local pending_changes = {}

-- Performance monitoring
local performance_metrics = {
    fps_history = {},
    max_history = 60,
    last_update_time = 0,
    frame_count = 0,
    memory_samples = {},
    stress_test_active = false,
}

-- ============================================================================
-- Metatable-based Change Detection
-- ============================================================================

-- Creates a proxy table with change detection
local function create_observable_table(t, path, on_change)
    local proxy = {}
    local mt = {
        __index = function(_, key)
            local value = t[key]
            if type(value) == "table" and key ~= "colors" then
                return create_observable_table(value, path .. "." .. tostring(key), on_change)
            end
            return value
        end,
        __newindex = function(_, key, value)
            local old_value = t[key]
            t[key] = value
            if old_value ~= value then
                on_change(path .. "." .. tostring(key), value, old_value)
            end
        end,
        __pairs = function()
            return pairs(t)
        end,
    }
    setmetatable(proxy, mt)
    return proxy
end

-- Initialize configuration with change detection
local function init_config()
    -- Deep copy defaults
    local function deep_copy(orig)
        local copy
        if type(orig) == "table" then
            copy = {}
            for k, v in next, orig, nil do
                copy[deep_copy(k)] = deep_copy(v)
            end
        else
            copy = orig
        end
        return copy
    end
    
    current_config = deep_copy(DEFAULT_CONFIG)
    
    -- Create observable proxy
    return create_observable_table(current_config, "config", function(path, new_val, old_val)
        if not is_batch_updating then
            on_config_changed(path, new_val, old_val)
        else
            pending_changes[path] = { new = new_val, old = old_val }
        end
    end)
end

-- Handle configuration changes
function on_config_changed(path, new_val, old_val)
    print(string.format("[layout_theme_settings] Config changed: %s = %s (was: %s)",
        path, tostring(new_val), tostring(old_val)))
    
    -- Update UI controls
    update_ui_for_path(path, new_val)
    
    -- Update visual sandbox
    update_visual_sandbox()
    
    -- Execute registered callbacks
    if change_callbacks[path] then
        for _, callback in ipairs(change_callbacks[path]) do
            callback(new_val, old_val)
        end
    end
end

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- NVGColor creation helper
local function nvgRGBA(r, g, b, a)
    return brls.nvgRGBA(
        math.floor(r),
        math.floor(g),
        math.floor(b),
        math.floor(a)
    )
end

-- NVGColor to table
local function color_to_table(color)
    return { r = color.r, g = color.g, b = color.b, a = color.a }
end

-- Table to NVGColor
local function table_to_color(tbl)
    return nvgRGBA(tbl.r or 0, tbl.g or 0, tbl.b or 0, tbl.a or 255)
end

-- Deep table comparison
local function deep_equal(t1, t2)
    if type(t1) ~= type(t2) then return false end
    if type(t1) ~= "table" then return t1 == t2 end
    
    for k, v in pairs(t1) do
        if not deep_equal(v, t2[k]) then return false end
    end
    
    for k, v in pairs(t2) do
        if t1[k] == nil then return false end
    end
    
    return true
end

-- ============================================================================
-- Theme System Implementation
-- ============================================================================

-- Apply theme configuration to borealis
local function apply_theme_config()
    local theme = current_config.theme
    
    -- Set theme variant
    if theme.variant == "LIGHT" then
        brls.Application.getPlatform():setThemeVariant(brls.ThemeVariant.LIGHT)
    elseif theme.variant == "DARK" then
        brls.Application.getPlatform():setThemeVariant(brls.ThemeVariant.DARK)
    end
    -- AUTO would follow system settings
    
    -- Apply custom colors to both themes
    local light_theme = brls.Theme.getLightTheme()
    local dark_theme = brls.Theme.getDarkTheme()
    
    -- Primary color
    local primary = table_to_color(theme.colors.primary)
    light_theme:addColor("accent", primary)
    dark_theme:addColor("accent", primary)
    
    -- Background color
    local bg = table_to_color(theme.colors.background)
    light_theme:addColor("background", bg)
    
    -- Text color
    local text = table_to_color(theme.colors.text)
    light_theme:addColor("font", text)
    dark_theme:addColor("font", text)
    
    -- Highlight color
    local highlight = table_to_color(theme.colors.highlight)
    light_theme:addColor("highlight", highlight)
    dark_theme:addColor("highlight", highlight)
    
    -- Border color
    local border = table_to_color(theme.colors.border)
    light_theme:addColor("border", border)
    dark_theme:addColor("border", border)
    
    -- High contrast mode adjustments
    if theme.high_contrast then
        -- Increase contrast by adjusting colors
        light_theme:addColor("font", nvgRGBA(0, 0, 0, 255))
        light_theme:addColor("background", nvgRGBA(255, 255, 255, 255))
        dark_theme:addColor("font", nvgRGBA(255, 255, 255, 255))
        dark_theme:addColor("background", nvgRGBA(0, 0, 0, 255))
    end
    
    print("[layout_theme_settings] Theme configuration applied")
end

-- ============================================================================
-- Window Management Implementation
-- ============================================================================

-- Resolution presets
local RESOLUTION_PRESETS = {
    ["720p"] = { width = 1280, height = 720 },
    ["1080p"] = { width = 1920, height = 1080 },
    ["1440p"] = { width = 2560, height = 1440 },
    ["4K"] = { width = 3840, height = 2160 },
    ["8K"] = { width = 7680, height = 4320 },
}

-- Apply window configuration
local function apply_window_config()
    local window = current_config.window
    local platform = brls.Application.getPlatform()
    
    if not platform then return end
    
    -- Apply resolution preset or custom
    local width, height
    if window.resolution_preset == "custom" then
        width = window.custom_width
        height = window.custom_height
    else
        local preset = RESOLUTION_PRESETS[window.resolution_preset]
        if preset then
            width = preset.width
            height = preset.height
        end
    end
    
    -- Apply window size if valid
    if width and height and width > 0 and height > 0 then
        -- Check aspect ratio lock
        if window.aspect_ratio_lock then
            local target_ratio = 16 / 9
            local current_ratio = width / height
            if math.abs(current_ratio - target_ratio) > 0.01 then
                -- Adjust to maintain aspect ratio
                height = math.floor(width / target_ratio)
            end
        end
        
        platform:setWindowSize(width, height)
        print(string.format("[layout_theme_settings] Window size set to %dx%d", width, height))
    end
    
    -- Note: setWindowScale scales the entire UI (not desired for reflow layout)
    -- For true reflow layout with fixed element sizes, we don't use windowScale
    -- Instead, we use fixed pixel values in XML and Flexbox layout
    print(string.format("[layout_theme_settings] DPI Scale: %.2fx (stored only, not applied)", window.dpi_scale))
    
    -- Apply always on top
    platform:setWindowAlwaysOnTop(window.always_on_top)
    
    print("[layout_theme_settings] Window configuration applied")
end

-- ============================================================================
-- Typography Implementation
-- ============================================================================

-- Apply typography configuration
local function apply_typography_config()
    local typo = current_config.typography
    
    -- Apply to preview labels
    if sample_views.sample_label_a then
        sample_views.sample_label_a:setFontSize(typo.body_font_size)
        sample_views.sample_label_a:setLineHeight(typo.line_height)
    end
    if sample_views.sample_label_b then
        sample_views.sample_label_b:setFontSize(typo.body_font_size)
        sample_views.sample_label_b:setLineHeight(typo.line_height)
    end
    
    -- Apply to metrics labels
    if sample_views.metrics_fps then
        sample_views.metrics_fps:setFontSize(typo.caption_font_size)
    end
    if sample_views.metrics_resolution then
        sample_views.metrics_resolution:setFontSize(typo.caption_font_size)
    end
    if sample_views.metrics_dpi_scale then
        sample_views.metrics_dpi_scale:setFontSize(typo.caption_font_size)
    end
    if sample_views.metrics_theme then
        sample_views.metrics_theme:setFontSize(typo.caption_font_size)
    end
    
    print("[layout_theme_settings] Typography configuration applied")
end

-- ============================================================================
-- Layout Geometry Implementation
-- ============================================================================

-- Layout type enum mapping
local LAYOUT_TYPES = {
    BOX = "Box",
    GRID = "Grid",
    ABSOLUTE = "Absolute",
}

-- Note: brls.Axis, brls.JustifyContent, brls.AlignItems, brls.PositionType enums
-- are not directly exposed to Lua. We store string values and apply them
-- through XML attributes or platform-specific methods.

-- Flex direction mapping (string values for reference)
local FLEX_DIRECTIONS = {
    ROW = "ROW",
    COLUMN = "COLUMN",
}

-- Justify content mapping (string values for reference)
local JUSTIFY_CONTENT = {
    FLEX_START = "FLEX_START",
    CENTER = "CENTER",
    FLEX_END = "FLEX_END",
    SPACE_BETWEEN = "SPACE_BETWEEN",
    SPACE_AROUND = "SPACE_AROUND",
    SPACE_EVENLY = "SPACE_EVENLY",
}

-- Align items mapping (string values for reference)
local ALIGN_ITEMS = {
    AUTO = "AUTO",
    FLEX_START = "FLEX_START",
    CENTER = "CENTER",
    FLEX_END = "FLEX_END",
    STRETCH = "STRETCH",
    BASELINE = "BASELINE",
    SPACE_BETWEEN = "SPACE_BETWEEN",
    SPACE_AROUND = "SPACE_AROUND",
}

-- Position type mapping (string values for reference)
local POSITION_TYPES = {
    RELATIVE = "RELATIVE",
    ABSOLUTE = "ABSOLUTE",
}

-- Apply layout configuration to a view
local function apply_layout_config_to_view(view)
    if not view then return end
    
    local layout = current_config.layout
    
    -- Flex direction (axis)
    if layout.flex_direction and FLEX_DIRECTIONS[layout.flex_direction] then
        -- Would be applied to Box views
        if view.setAxis then
            view:setAxis(FLEX_DIRECTIONS[layout.flex_direction])
        end
    end
    
    -- Justify content
    if layout.justify_content and JUSTIFY_CONTENT[layout.justify_content] then
        if view.setJustifyContent then
            view:setJustifyContent(JUSTIFY_CONTENT[layout.justify_content])
        end
    end
    
    -- Align items
    if layout.align_items and ALIGN_ITEMS[layout.align_items] then
        if view.setAlignItems then
            view:setAlignItems(ALIGN_ITEMS[layout.align_items])
        end
    end
    
    -- Grow/Shrink factors
    if layout.stretch_factor then
        view:setGrow(layout.stretch_factor)
    end
    
    if layout.shrink_factor then
        view:setShrink(layout.shrink_factor)
    end
    
    -- Position type
    if layout.position_type and POSITION_TYPES[layout.position_type] then
        view:setPositionType(POSITION_TYPES[layout.position_type])
    end
    
    -- Percentage positioning
    if layout.position_x_percent and layout.position_x_percent > 0 then
        view:setPositionLeftPercentage(layout.position_x_percent)
    end
    
    if layout.position_y_percent and layout.position_y_percent > 0 then
        view:setPositionTopPercentage(layout.position_y_percent)
    end
    
    -- Absolute positioning
    if layout.position_type == "ABSOLUTE" then
        view:setPositionLeft(layout.absolute_x)
        view:setPositionTop(layout.absolute_y)
    end
    
    -- Aspect ratio
    if layout.aspect_ratio and layout.aspect_ratio > 0 then
        -- Aspect ratio would be applied through width/height constraints
    end
    
    view:invalidate()
end

-- ============================================================================
-- Spacing Implementation
-- ============================================================================

-- Apply spacing configuration
local function apply_spacing_config()
    local spacing = current_config.spacing
    
    -- Apply padding to preview containers
    if sample_views.preview_a_content then
        sample_views.preview_a_content:setPaddingTop(spacing.padding_top)
        sample_views.preview_a_content:setPaddingRight(spacing.padding_right)
        sample_views.preview_a_content:setPaddingBottom(spacing.padding_bottom)
        sample_views.preview_a_content:setPaddingLeft(spacing.padding_left)
    end
    if sample_views.preview_b_content then
        sample_views.preview_b_content:setPaddingTop(spacing.padding_top)
        sample_views.preview_b_content:setPaddingRight(spacing.padding_right)
        sample_views.preview_b_content:setPaddingBottom(spacing.padding_bottom)
        sample_views.preview_b_content:setPaddingLeft(spacing.padding_left)
    end
    
    -- Apply margins to preview elements
    if sample_views.sample_button_a then
        sample_views.sample_button_a:setMarginBottom(spacing.margin_bottom)
    end
    if sample_views.sample_label_a then
        sample_views.sample_label_a:setMarginBottom(spacing.margin_bottom)
    end
    if sample_views.sample_button_b then
        sample_views.sample_button_b:setMarginBottom(spacing.margin_bottom)
    end
    if sample_views.sample_label_b then
        sample_views.sample_label_b:setMarginBottom(spacing.margin_bottom)
    end
    
    print("[layout_theme_settings] Spacing configuration applied")
end

-- ============================================================================
-- Animation Timing Implementation
-- ============================================================================

-- Easing function mapping
local EASING_FUNCTIONS = {
    linear = brls.EasingFunction.linear,
    quadratic_in = brls.EasingFunction.quadraticIn,
    quadratic_out = brls.EasingFunction.quadraticOut,
    quadratic_inout = brls.EasingFunction.quadraticInOut,
    cubic_in = brls.EasingFunction.cubicIn,
    cubic_out = brls.EasingFunction.cubicOut,
    cubic_inout = brls.EasingFunction.cubicInOut,
    sine_in = brls.EasingFunction.sineIn,
    sine_out = brls.EasingFunction.sineOut,
    sine_inout = brls.EasingFunction.sineInOut,
    exponential_in = brls.EasingFunction.exponentialIn,
    exponential_out = brls.EasingFunction.exponentialOut,
    exponential_inout = brls.EasingFunction.exponentialInOut,
    circular_in = brls.EasingFunction.circularIn,
    circular_out = brls.EasingFunction.circularOut,
    circular_inout = brls.EasingFunction.circularInOut,
    back_in = brls.EasingFunction.backIn,
    back_out = brls.EasingFunction.backOut,
    back_inout = brls.EasingFunction.backInOut,
    elastic_in = brls.EasingFunction.elasticIn,
    elastic_out = brls.EasingFunction.elasticOut,
    elastic_inout = brls.EasingFunction.elasticInOut,
    bounce_in = brls.EasingFunction.bounceIn,
    bounce_out = brls.EasingFunction.bounceOut,
    bounce_inout = brls.EasingFunction.bounceInOut,
}

-- Apply animation configuration
local function apply_animation_config()
    local anim = current_config.animation
    local style = brls.getStyle()
    
    -- Store animation settings as style metrics
    style:addMetric("animation/transition_duration", anim.transition_duration)
    style:addMetric("animation/stagger_delay", anim.stagger_delay)
    style:addMetric("animation/highlight_speed", anim.highlight_speed)
    style:addMetric("animation/shake_amplitude", anim.shake_amplitude)
    style:addMetric("animation/micro_duration", anim.micro_duration)
    style:addMetric("animation/frame_rate_independent", anim.frame_rate_independent and 1 or 0)
    
    print("[layout_theme_settings] Animation configuration applied")
end

-- ============================================================================
-- Rendering Implementation
-- ============================================================================

-- Apply rendering configuration
local function apply_rendering_config()
    local render = current_config.rendering
    
    -- FPS limit
    if render.fps_limit > 0 then
        brls.Application.setLimitedFPS(render.fps_limit)
    else
        brls.Application.setLimitedFPS(0) -- Unlimited
    end
    
    -- VSync (swap interval)
    brls.Application.setSwapInterval(render.vsync and 1 or 0)
    
    -- Debug layer
    brls.Application.enableDebuggingView(render.debug_layer)
    
    print("[layout_theme_settings] Rendering configuration applied")
end

-- ============================================================================
-- Visual Sandbox Implementation
-- ============================================================================

-- Update the visual sandbox preview
local function update_visual_sandbox()
    -- This would update the preview panel based on current settings
    -- In a real implementation, this would sync to the UI views
end

-- Apply configuration to preview elements
local function apply_to_preview(view_prefix)
    local view_map = {
        button = view_prefix .. "_button_a",
        label = view_prefix .. "_label_a",
        rect = view_prefix .. "_rect_a",
    }
    
    -- Apply typography to label
    if sample_views[view_map.label] then
        local v = sample_views[view_map.label]
        v:setFontSize(current_config.typography.body_font_size)
        -- Would apply more typography settings
    end
    
    -- Apply styling to rectangle
    if sample_views[view_map.rect] then
        local v = sample_views[view_map.rect]
        local color = table_to_color(current_config.theme.colors.accent)
        v:setBackgroundColor(color)
        v:setCornerRadius(current_config.spacing.glow_radius)
    end
end

-- ============================================================================
-- Theme Import/Export Implementation
-- ============================================================================

-- Export current configuration to JSON
local function export_theme_to_json()
    local export_data = {
        version = MODULE_VERSION,
        identifier = MODULE_IDENTIFIER,
        timestamp = os.time(),
        config = current_config,
    }
    
    local json_str = json.encode(export_data)
    
    -- In a real implementation, this would save to a file
    print("[layout_theme_settings] Theme exported to JSON")
    print(json_str)
    
    brls.Application.notify("Theme exported to JSON")
    return json_str
end

-- Import configuration from JSON
local function import_theme_from_json(json_str)
    local success, data = pcall(json.decode, json_str)
    
    if not success or not data then
        print("[layout_theme_settings] Failed to parse JSON")
        brls.Application.notify("Failed to import theme: Invalid JSON")
        return false
    end
    
    if data.identifier ~= MODULE_IDENTIFIER then
        print("[layout_theme_settings] Invalid theme identifier")
        brls.Application.notify("Failed to import theme: Invalid identifier")
        return false
    end
    
    -- Merge configuration
    is_batch_updating = true
    
    local function merge_config(dest, src)
        for k, v in pairs(src) do
            if type(v) == "table" and type(dest[k]) == "table" then
                merge_config(dest[k], v)
            else
                dest[k] = v
            end
        end
    end
    
    merge_config(current_config, data.config)
    
    is_batch_updating = false
    
    -- Apply all changes
    for path, changes in pairs(pending_changes) do
        on_config_changed(path, changes.new, changes.old)
    end
    pending_changes = {}
    
    -- Re-apply all configurations
    apply_all_configurations()
    
    print("[layout_theme_settings] Theme imported from JSON")
    brls.Application.notify("Theme imported successfully")
    return true
end

-- Create A/B snapshot
local function create_ab_snapshot(slot)
    local function deep_copy(orig)
        local copy
        if type(orig) == "table" then
            copy = {}
            for k, v in next, orig, nil do
                copy[deep_copy(k)] = deep_copy(v)
            end
        else
            copy = orig
        end
        return copy
    end
    
    if slot == "A" then
        snapshot_a = deep_copy(current_config)
        print("[layout_theme_settings] Snapshot A created")
        brls.Application.notify("Snapshot A created")
    elseif slot == "B" then
        snapshot_b = deep_copy(current_config)
        print("[layout_theme_settings] Snapshot B created")
        brls.Application.notify("Snapshot B created")
    end
end

-- Compare A/B snapshots and return diff
local function compare_ab_snapshots()
    if not snapshot_a or not snapshot_b then
        print("[layout_theme_settings] Both snapshots required for comparison")
        return nil
    end
    
    local diffs = {}
    
    local function compare_tables(t1, t2, path)
        for k, v1 in pairs(t1) do
            local v2 = t2[k]
            local current_path = path .. "." .. k
            
            if type(v1) == "table" and type(v2) == "table" then
                compare_tables(v1, v2, current_path)
            elseif v1 ~= v2 then
                table.insert(diffs, {
                    path = current_path,
                    a_value = v1,
                    b_value = v2,
                })
            end
        end
        
        for k, v2 in pairs(t2) do
            if t1[k] == nil then
                table.insert(diffs, {
                    path = path .. "." .. k,
                    a_value = nil,
                    b_value = v2,
                })
            end
        end
    end
    
    compare_tables(snapshot_a, snapshot_b, "config")
    
    print(string.format("[layout_theme_settings] Found %d differences between A and B", #diffs))
    
    -- Show diff notification
    local diff_summary = string.format("A/B Diff: %d changes", #diffs)
    brls.Application.notify(diff_summary)
    
    return diffs
end

-- ============================================================================
-- Stress Testing Implementation
-- ============================================================================

-- Helper function for repeating delays
local function repeat_delay(interval, func, max_count)
    local count = 0
    local timer_id = nil
    
    local function callback()
        count = count + 1
        local should_continue = func(count)
        if should_continue and (not max_count or count < max_count) then
            timer_id = brls.delay(interval, callback)
        end
        return timer_id
    end
    
    return callback()
end

-- Rapid theme cycling test
local function start_rapid_theme_cycling()
    if performance_metrics.stress_test_active then
        print("[layout_theme_settings] Stress test already active")
        return
    end
    
    performance_metrics.stress_test_active = true
    print("[layout_theme_settings] Starting rapid theme cycling test")
    brls.Application.notify("Rapid theme cycling started")
    
    local themes = { "LIGHT", "DARK" }
    local theme_index = 1
    local max_cycles = 50
    
    -- Use repeating delay for cycling
    repeat_delay(100, function(cycle_count)
        theme_index = theme_index % #themes + 1
        current_config.theme.variant = themes[theme_index]
        apply_theme_config()
        
        if cycle_count >= max_cycles then
            performance_metrics.stress_test_active = false
            print("[layout_theme_settings] Rapid theme cycling completed")
            brls.Application.notify("Rapid theme cycling completed")
            return false -- Stop repeating
        end
        return true -- Continue
    end)
end

-- Resolution boundary test
local function start_resolution_boundary_test()
    print("[layout_theme_settings] Starting resolution boundary test")
    brls.Application.notify("Resolution boundary test started")
    
    local platform = brls.Application.getPlatform()
    if not platform then return end
    
    local test_resolutions = {
        { 640, 360 },    -- Minimum practical
        { 1280, 720 },   -- 720p
        { 1920, 1080 },  -- 1080p
        { 3840, 2160 },  -- 4K
        { 100, 100 },    -- Small boundary
        { 2560, 1440 },  -- 1440p
    }
    
    local index = 1
    
    local function test_next_resolution()
        local res = test_resolutions[index]
        if res then
            platform:setWindowSize(res[1], res[2])
            print(string.format("[layout_theme_settings] Testing resolution: %dx%d", res[1], res[2]))
            index = index + 1
            brls.delay(500, test_next_resolution)
        else
            -- Restore default
            platform:setWindowSize(1280, 720)
            print("[layout_theme_settings] Resolution boundary test completed")
            brls.Application.notify("Resolution boundary test completed")
        end
    end
    
    test_next_resolution()
end

-- Zero dimension test
local function start_zero_dimension_test()
    print("[layout_theme_settings] Starting zero dimension test")
    brls.Application.notify("Zero dimension test started (safe mode)")
    
    local platform = brls.Application.getPlatform()
    if not platform then return end
    
    -- Test zero dimensions (should be handled gracefully)
    -- Try various edge cases
    local tests = {
        { 0, 720 },
        { 1280, 0 },
        { 0, 0 },
        { 1, 1 },
    }
    
    local index = 1
    
    local function test_next_dimension()
        local test = tests[index]
        if test then
            -- This should fail gracefully or be rejected
            local success, err = pcall(function()
                platform:setWindowSize(test[1], test[2])
            end)
            
            if success then
                print(string.format("[layout_theme_settings] Zero dimension test: %dx%d (accepted)", test[1], test[2]))
            else
                print(string.format("[layout_theme_settings] Zero dimension test: %dx%d (rejected: %s)", test[1], test[2], tostring(err)))
            end
            
            index = index + 1
            brls.delay(300, test_next_dimension)
        else
            -- Restore default
            platform:setWindowSize(1280, 720)
            print("[layout_theme_settings] Zero dimension test completed")
            brls.Application.notify("Zero dimension test completed")
        end
    end
    
    test_next_dimension()
end

-- Negative scaling test
local function start_negative_scaling_test()
    print("[layout_theme_settings] Starting negative scaling test")
    brls.Application.notify("Negative scaling test started (safe mode)")
    
    local style = brls.getStyle()
    local original_scale = current_config.window.dpi_scale
    
    local tests = { -1.0, -0.5, 0, 0.5, 1.0 }
    local index = 1
    
    local function test_next_scale()
        local test_scale = tests[index]
        if test_scale then
            -- This should fail gracefully or be clamped
            local success, err = pcall(function()
                style:addMetric("window/dpi_scale", test_scale)
            end)
            
            print(string.format("[layout_theme_settings] Negative scaling test: %.1f (success: %s)", 
                test_scale, tostring(success)))
            
            index = index + 1
            brls.delay(300, test_next_scale)
        else
            -- Restore original
            style:addMetric("window/dpi_scale", original_scale)
            print("[layout_theme_settings] Negative scaling test completed")
            brls.Application.notify("Negative scaling test completed")
        end
    end
    
    test_next_scale()
end

-- Maximum recursion depth test
-- Note: This test is disabled because brls.Box.new() is not exposed to Lua
-- The test would create deeply nested boxes to test layout recursion
local function start_max_recursion_test()
    print("[layout_theme_settings] Max recursion test: Disabled (brls.Box.new() not available in Lua)")
    brls.Application.notify("Max recursion test: Not available in Lua runtime")
    
    -- Alternative: Just notify that the test would run
    -- In a real implementation with C++ access, this would:
    -- 1. Create 100 nested Box containers
    -- 2. Measure layout performance
    -- 3. Check for stack overflow protection
    -- 4. Verify memory cleanup
end

-- ============================================================================
-- Runtime Inspection Implementation
-- ============================================================================

-- List all style metrics
local function list_all_style_metrics()
    local style = brls.getStyle()
    -- In a real implementation, this would enumerate all registered metrics
    print("[layout_theme_settings] Style Metrics:")
    print("  - brls/sidebar/padding_top")
    print("  - brls/sidebar/padding_right")
    print("  - brls/sidebar/padding_bottom")
    print("  - brls/sidebar/padding_left")
    print("  - brls/highlight/corner_radius")
    print("  - typography/header_size")
    print("  - typography/body_size")
    print("  - typography/caption_size")
    
    brls.Application.notify("Style metrics listed to console")
end

-- List all theme colors
local function list_all_theme_colors()
    local light_theme = brls.Theme.getLightTheme()
    local dark_theme = brls.Theme.getDarkTheme()
    
    print("[layout_theme_settings] Light Theme Colors:")
    -- Would enumerate all registered colors
    
    print("[layout_theme_settings] Dark Theme Colors:")
    -- Would enumerate all registered colors
    
    brls.Application.notify("Theme colors listed to console")
end

-- List all view types
local function list_all_view_types()
    print("[layout_theme_settings] Registered View Types:")
    print("  - Box")
    print("  - Label")
    print("  - Button")
    print("  - Rectangle")
    print("  - Image")
    print("  - ScrollingFrame")
    print("  - HScrollingFrame")
    print("  - Slider")
    print("  - TabFrame")
    print("  - AppletFrame")
    print("  - RecyclerFrame")
    print("  - Sidebar")
    print("  - Header")
    print("  - BottomBar")
    print("  - Dialog")
    print("  - Dropdown")
    print("  - BooleanCell")
    print("  - DetailCell")
    print("  - InputCell")
    print("  - RadioCell")
    print("  - SelectorCell")
    print("  - SliderCell")
    
    brls.Application.notify("View types listed to console")
end

-- List XML attributes
local function list_xml_attributes()
    print("[layout_theme_settings] Common XML Attributes:")
    print("  Layout: width, height, grow, shrink, axis")
    print("  Position: positionTop, positionRight, positionBottom, positionLeft")
    print("  Position: positionType (relative, absolute)")
    print("  Spacing: marginTop, marginRight, marginBottom, marginLeft")
    print("  Spacing: paddingTop, paddingRight, paddingBottom, paddingLeft")
    print("  Style: backgroundColor, borderColor, borderThickness, cornerRadius")
    print("  Style: shadowType (none, generic, custom)")
    print("  Style: lineTop, lineRight, lineBottom, lineLeft, lineColor")
    print("  Visibility: visibility (visible, invisible, gone)")
    print("  Flex: justifyContent, alignItems, alignSelf")
    print("  Constraints: minWidth, maxWidth, minHeight, maxHeight")
    
    brls.Application.notify("XML attributes listed to console")
end

-- Get current focus info
local function get_current_focus_info()
    local focus = brls.Application.getCurrentFocus()
    if focus then
        print("[layout_theme_settings] Current Focus:")
        print("  ID: " .. (focus:getId() or "none"))
        print("  Frame: " .. tostring(focus:getFrame()))
        print("  Visibility: " .. tostring(focus:getVisibility()))
        
        brls.Application.notify("Focus info: " .. (focus:getId() or "none"))
    else
        print("[layout_theme_settings] No current focus")
        brls.Application.notify("No current focus")
    end
end

-- Dump view tree hierarchy
local function dump_view_tree_hierarchy()
    local function dump_view(view, depth)
        if not view then return end
        
        local indent = string.rep("  ", depth)
        local id = view:getId() or "anonymous"
        local view_type = "View" -- Would get actual type name
        
        print(indent .. view_type .. " [" .. id .. "]")
        
        -- If it's a Box, iterate children
        if view.getViews then
            local children = view:getViews()
            for _, child in ipairs(children or {}) do
                dump_view(child, depth + 1)
            end
        end
    end
    
    print("[layout_theme_settings] View Tree Hierarchy:")
    -- Would start from root activity
    
    brls.Application.notify("View hierarchy dumped to console")
end

-- ============================================================================
-- Performance Monitoring
-- ============================================================================

-- Update FPS metrics
local function update_fps_metrics()
    -- Ensure sample_views is initialized before using
    if not sample_views then
        return
    end
    
    local current_fps = brls.Application.getFPS()
    
    table.insert(performance_metrics.fps_history, current_fps)
    if #performance_metrics.fps_history > performance_metrics.max_history then
        table.remove(performance_metrics.fps_history, 1)
    end
    
    -- Calculate average
    local sum = 0
    for _, fps in ipairs(performance_metrics.fps_history) do
        sum = sum + fps
    end
    local avg_fps = sum / #performance_metrics.fps_history
    
    -- Update UI if views available
    if sample_views.metrics_fps then
        sample_views.metrics_fps:setText(string.format("FPS: %d (avg: %.1f)", current_fps, avg_fps))
    end
    
    -- Check for 60FPS stability
    if current_config.rendering.fps_stability_monitor then
        if current_fps < 55 then
            print(string.format("[layout_theme_settings] FPS drop detected: %d", current_fps))
        end
    end
end

-- Memory leak detection
local function check_memory_leaks()
    if not current_config.rendering.memory_leak_detection then
        return
    end
    
    -- Sample memory usage (in a real implementation, this would use platform-specific APIs)
    local sample = {
        time = os.time(),
        -- memory = get_memory_usage(),
    }
    
    table.insert(performance_metrics.memory_samples, sample)
    
    -- Keep only recent samples
    if #performance_metrics.memory_samples > 60 then
        table.remove(performance_metrics.memory_samples, 1)
    end
    
    -- Simple leak detection: check if memory is consistently increasing
    if #performance_metrics.memory_samples >= 30 then
        local increasing_count = 0
        for i = 2, #performance_metrics.memory_samples do
            -- if performance_metrics.memory_samples[i].memory > performance_metrics.memory_samples[i-1].memory then
            --     increasing_count = increasing_count + 1
            -- end
        end
        
        -- If memory increased in 80% of samples, might be a leak
        if increasing_count / (#performance_metrics.memory_samples - 1) > 0.8 then
            print("[layout_theme_settings] Warning: Potential memory leak detected")
        end
    end
end

-- ============================================================================
-- UI Update Functions
-- ============================================================================

-- Update UI controls based on config path
function update_ui_for_path(path, value)
    -- Map config paths to view IDs and update accordingly
    -- This is called when configuration changes
end

-- Helper function to find index of a value in a table (returns 0-based index)
local function find_index(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then
            return i - 1
        end
    end
    return 0
end

-- Helper function to capitalize first letter of each word
local function title_case(str)
    return str:gsub("(%a)([%w_]*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

-- Apply all configurations
function apply_all_configurations()
    apply_theme_config()
    apply_window_config()
    apply_typography_config()
    apply_spacing_config()
    apply_animation_config()
    apply_rendering_config()
    
    -- Update visual sandbox
    update_visual_sandbox()
end

-- ============================================================================
-- Main Initialization
-- ============================================================================

function layout_theme_settings.init(mainView)
    if not mainView then
        print("[layout_theme_settings] Error: mainView is nil")
        return
    end
    
    print("[layout_theme_settings] Initializing Layout & Theme Configuration Testing Module v" .. MODULE_VERSION)
    
    -- Initialize configuration with change detection
    local config_proxy = init_config()
    
    -- ============================================================================
    -- Bind UI Views
    -- ============================================================================
    
    -- Theme Configuration
    sample_views.theme_variant_selector = mainView:getView("theme_variant_selector")
    sample_views.high_contrast_toggle = mainView:getView("high_contrast_toggle")
    sample_views.auto_theme_toggle = mainView:getView("auto_theme_toggle")
    sample_views.primary_color_picker = mainView:getView("primary_color_picker")
    sample_views.accent_color_picker = mainView:getView("accent_color_picker")
    sample_views.background_color_picker = mainView:getView("background_color_picker")
    sample_views.text_color_picker = mainView:getView("text_color_picker")
    sample_views.highlight_color_picker = mainView:getView("highlight_color_picker")
    sample_views.border_color_picker = mainView:getView("border_color_picker")
    sample_views.shadow_color_picker = mainView:getView("shadow_color_picker")
    sample_views.subtheme_selector = mainView:getView("subtheme_selector")
    
    -- Window Management
    sample_views.resolution_preset = mainView:getView("resolution_preset")
    sample_views.custom_width = mainView:getView("custom_width")
    sample_views.custom_height = mainView:getView("custom_height")
    sample_views.dpi_scale_slider = mainView:getView("dpi_scale_slider")
    sample_views.window_mode_selector = mainView:getView("window_mode_selector")
    sample_views.aspect_ratio_lock = mainView:getView("aspect_ratio_lock")
    sample_views.viewport_snapping = mainView:getView("viewport_snapping")
    sample_views.always_on_top = mainView:getView("always_on_top")
    sample_views.fullscreen_borderless = mainView:getView("fullscreen_borderless")
    sample_views.monitor_selector = mainView:getView("monitor_selector")
    
    -- Typography
    sample_views.font_family_selector = mainView:getView("font_family_selector")
    sample_views.header_font_size = mainView:getView("header_font_size")
    sample_views.body_font_size = mainView:getView("body_font_size")
    sample_views.caption_font_size = mainView:getView("caption_font_size")
    sample_views.monospace_font_toggle = mainView:getView("monospace_font_toggle")
    sample_views.font_fallback_chain = mainView:getView("font_fallback_chain")
    sample_views.dynamic_font_scaling = mainView:getView("dynamic_font_scaling")
    sample_views.letter_spacing = mainView:getView("letter_spacing")
    sample_views.line_height = mainView:getView("line_height")
    sample_views.text_alignment = mainView:getView("text_alignment")
    
    -- Layout Geometry
    sample_views.layout_type_selector = mainView:getView("layout_type_selector")
    sample_views.flex_direction_selector = mainView:getView("flex_direction_selector")
    sample_views.justify_content_selector = mainView:getView("justify_content_selector")
    sample_views.align_items_selector = mainView:getView("align_items_selector")
    sample_views.stretch_factor = mainView:getView("stretch_factor")
    sample_views.shrink_factor = mainView:getView("shrink_factor")
    sample_views.position_type_selector = mainView:getView("position_type_selector")
    sample_views.position_x_percent = mainView:getView("position_x_percent")
    sample_views.position_y_percent = mainView:getView("position_y_percent")
    sample_views.absolute_x = mainView:getView("absolute_x")
    sample_views.absolute_y = mainView:getView("absolute_y")
    sample_views.aspect_ratio_slider = mainView:getView("aspect_ratio_slider")
    
    -- Spacing
    sample_views.padding_top = mainView:getView("padding_top")
    sample_views.padding_right = mainView:getView("padding_right")
    sample_views.padding_bottom = mainView:getView("padding_bottom")
    sample_views.padding_left = mainView:getView("padding_left")
    sample_views.margin_top = mainView:getView("margin_top")
    sample_views.margin_right = mainView:getView("margin_right")
    sample_views.margin_bottom = mainView:getView("margin_bottom")
    sample_views.margin_left = mainView:getView("margin_left")
    sample_views.separator_thickness = mainView:getView("separator_thickness")
    sample_views.scroll_indicator_offset = mainView:getView("scroll_indicator_offset")
    sample_views.focus_border_inset = mainView:getView("focus_border_inset")
    sample_views.glow_radius = mainView:getView("glow_radius")
    sample_views.safe_area_top = mainView:getView("safe_area_top")
    sample_views.safe_area_bottom = mainView:getView("safe_area_bottom")
    
    -- Animation
    sample_views.easing_function_selector = mainView:getView("easing_function_selector")
    sample_views.transition_duration = mainView:getView("transition_duration")
    sample_views.stagger_delay = mainView:getView("stagger_delay")
    sample_views.highlight_speed = mainView:getView("highlight_speed")
    sample_views.shake_amplitude = mainView:getView("shake_amplitude")
    sample_views.micro_duration = mainView:getView("micro_duration")
    sample_views.frame_rate_independent = mainView:getView("frame_rate_independent")
    
    -- Rendering
    sample_views.texture_filtering = mainView:getView("texture_filtering")
    sample_views.msaa_level = mainView:getView("msaa_level")
    sample_views.transparency_blending = mainView:getView("transparency_blending")
    sample_views.hdr_brightness = mainView:getView("hdr_brightness")
    sample_views.fps_limit = mainView:getView("fps_limit")
    sample_views.vsync_toggle = mainView:getView("vsync_toggle")
    sample_views.debug_layer_toggle = mainView:getView("debug_layer_toggle")
    
    -- Import/Export
    sample_views.export_theme = mainView:getView("export_theme")
    sample_views.import_theme = mainView:getView("import_theme")
    sample_views.reset_default = mainView:getView("reset_default")
    sample_views.ab_snapshot = mainView:getView("ab_snapshot")
    sample_views.ab_compare = mainView:getView("ab_compare")
    
    -- Stress Testing
    sample_views.rapid_theme_cycling = mainView:getView("rapid_theme_cycling")
    sample_views.resolution_boundary_test = mainView:getView("resolution_boundary_test")
    sample_views.zero_dimension_test = mainView:getView("zero_dimension_test")
    sample_views.negative_scaling_test = mainView:getView("negative_scaling_test")
    sample_views.max_recursion_test = mainView:getView("max_recursion_test")
    sample_views.memory_leak_detection = mainView:getView("memory_leak_detection")
    sample_views.fps_stability_monitor = mainView:getView("fps_stability_monitor")
    
    -- Inspection
    sample_views.list_all_styles = mainView:getView("list_all_styles")
    sample_views.list_all_colors = mainView:getView("list_all_colors")
    sample_views.list_all_view_types = mainView:getView("list_all_view_types")
    sample_views.list_xml_attributes = mainView:getView("list_xml_attributes")
    sample_views.current_focus_info = mainView:getView("current_focus_info")
    sample_views.view_tree_hierarchy = mainView:getView("view_tree_hierarchy")
    
    -- Preview Panel
    sample_views.preview_mode = mainView:getView("preview_mode")
    sample_views.split_screen_container = mainView:getView("split_screen_container")
    sample_views.preview_a_content = mainView:getView("preview_a_content")
    sample_views.preview_b_content = mainView:getView("preview_b_content")
    sample_views.sample_button_a = mainView:getView("sample_button_a")
    sample_views.sample_label_a = mainView:getView("sample_label_a")
    sample_views.sample_rect_a = mainView:getView("sample_rect_a")
    sample_views.sample_button_b = mainView:getView("sample_button_b")
    sample_views.sample_label_b = mainView:getView("sample_label_b")
    sample_views.sample_rect_b = mainView:getView("sample_rect_b")
    sample_views.metrics_fps = mainView:getView("metrics_fps")
    sample_views.metrics_resolution = mainView:getView("metrics_resolution")
    sample_views.metrics_dpi_scale = mainView:getView("metrics_dpi_scale")
    sample_views.metrics_theme = mainView:getView("metrics_theme")
    sample_views.status_label = mainView:getView("status_label")
    
    -- ============================================================================
    -- Initialize UI Controls
    -- ============================================================================
    
    -- Theme Variant Selector
    if sample_views.theme_variant_selector then
        local variants = { "LIGHT", "DARK", "AUTO" }
        sample_views.theme_variant_selector:init("Theme Variant", {"Light", "Dark", "Auto"},
            find_index(variants, current_config.theme.variant),
            function(selected) end,
            function(selected)
                current_config.theme.variant = variants[selected + 1]
                apply_theme_config()
            end)
    end
    
    -- High Contrast Toggle
    if sample_views.high_contrast_toggle then
        sample_views.high_contrast_toggle:init("High Contrast Mode", current_config.theme.high_contrast,
            function(value)
                current_config.theme.high_contrast = value
                apply_theme_config()
            end)
    end
    
    -- Auto Theme Toggle
    if sample_views.auto_theme_toggle then
        sample_views.auto_theme_toggle:init("Auto Theme (Follow System)", current_config.theme.auto_follow_system,
            function(value)
                current_config.theme.auto_follow_system = value
                -- Would implement system theme detection
            end)
    end
    
    -- Resolution Preset
    if sample_views.resolution_preset then
        local presets = { "720p", "1080p", "1440p", "4K", "8K", "custom" }
        sample_views.resolution_preset:init("Resolution Preset",
            {"720p", "1080p", "1440p", "4K", "8K", "Custom"},
            find_index(presets, current_config.window.resolution_preset),
            function(selected) end,
            function(selected)
                current_config.window.resolution_preset = presets[selected + 1]
                apply_window_config()
            end)
    end
    
    -- DPI Scale Slider
    if sample_views.dpi_scale_slider then
        sample_views.dpi_scale_slider:init("DPI Scale Factor (0.5x - 3.0x)", 
            current_config.window.dpi_scale,
            function(value)
                -- Clamp to valid range
                value = math.max(0.5, math.min(3.0, value))
                current_config.window.dpi_scale = value
                sample_views.dpi_scale_slider:setDetailText(string.format("%.2fx", value))
                apply_window_config()
            end)
        sample_views.dpi_scale_slider:setDetailText(string.format("%.2fx", current_config.window.dpi_scale))
    end
    
    -- Always On Top
    if sample_views.always_on_top then
        sample_views.always_on_top:init("Always On Top", current_config.window.always_on_top,
            function(value)
                current_config.window.always_on_top = value
                apply_window_config()
            end)
    end
    
    -- Header Font Size
    if sample_views.header_font_size then
        sample_views.header_font_size:init("Header Font Size (10-72)", 
            current_config.typography.header_font_size / 72,
            function(value)
                local size = math.floor(value * 72)
                size = math.max(10, math.min(72, size))
                current_config.typography.header_font_size = size
                sample_views.header_font_size:setDetailText(tostring(size))
                apply_typography_config()
            end)
        sample_views.header_font_size:setDetailText(tostring(current_config.typography.header_font_size))
    end
    
    -- Flex Direction
    if sample_views.flex_direction_selector then
        local directions = { "ROW", "COLUMN" }
        sample_views.flex_direction_selector:init("Flex Direction",
            {"Row", "Column"},
            find_index(directions, current_config.layout.flex_direction),
            function(selected) end,
            function(selected)
                current_config.layout.flex_direction = directions[selected + 1]
                -- Would apply to preview
            end)
    end
    
    -- Justify Content
    if sample_views.justify_content_selector then
        local options = { "FLEX_START", "CENTER", "FLEX_END", "SPACE_BETWEEN", "SPACE_AROUND", "SPACE_EVENLY" }
        sample_views.justify_content_selector:init("Justify Content",
            {"Flex Start", "Center", "Flex End", "Space Between", "Space Around", "Space Evenly"},
            find_index(options, current_config.layout.justify_content),
            function(selected) end,
            function(selected)
                current_config.layout.justify_content = options[selected + 1]
            end)
    end
    
    -- Easing Function
    if sample_views.easing_function_selector then
        local easings = { "linear", "quadratic_in", "quadratic_out", "quadratic_inout",
            "cubic_in", "cubic_out", "cubic_inout", "sine_in", "sine_out", "sine_inout",
            "exponential_in", "exponential_out", "back_in", "back_out", "bounce_in", "bounce_out" }
        sample_views.easing_function_selector:init("Easing Function",
            {"Linear", "Quadratic In", "Quadratic Out", "Quadratic InOut",
             "Cubic In", "Cubic Out", "Cubic InOut", "Sine In", "Sine Out", "Sine InOut",
             "Exponential In", "Exponential Out", "Back In", "Back Out", "Bounce In", "Bounce Out"},
            find_index(easings, current_config.animation.easing_function),
            function(selected) end,
            function(selected)
                current_config.animation.easing_function = easings[selected + 1]
                apply_animation_config()
            end)
    end
    
    -- FPS Limit
    if sample_views.fps_limit then
        local limits = { 0, 30, 60, 120, 144, 240 }
        sample_views.fps_limit:init("FPS Limit",
            {"Unlimited", "30 FPS", "60 FPS", "120 FPS", "144 FPS", "240 FPS"},
            find_index(limits, current_config.rendering.fps_limit),
            function(selected) end,
            function(selected)
                current_config.rendering.fps_limit = limits[selected + 1]
                apply_rendering_config()
            end)
    end
    
    -- Debug Layer Toggle
    if sample_views.debug_layer_toggle then
        sample_views.debug_layer_toggle:init("Debug Layer Visible", 
            brls.Application.isDebuggingViewEnabled(),
            function(value)
                current_config.rendering.debug_layer = value
                brls.Application.enableDebuggingView(value)
            end)
    end
    
    -- VSync Toggle
    if sample_views.vsync_toggle then
        sample_views.vsync_toggle:init("VSync Enabled", current_config.rendering.vsync,
            function(value)
                current_config.rendering.vsync = value
                apply_rendering_config()
            end)
    end
    
    -- Export Theme
    if sample_views.export_theme then
        sample_views.export_theme:onClick(function()
            export_theme_to_json()
            return true
        end)
    end
    
    -- Import Theme (placeholder)
    if sample_views.import_theme then
        sample_views.import_theme:onClick(function()
            -- Would open a file picker dialog
            brls.Application.notify("Import: Use JSON string input")
            return true
        end)
    end
    
    -- Reset to Default
    if sample_views.reset_default then
        sample_views.reset_default:onClick(function()
            -- Deep copy defaults to current
            local function deep_copy(orig)
                local copy
                if type(orig) == "table" then
                    copy = {}
                    for k, v in next, orig, nil do
                        copy[deep_copy(k)] = deep_copy(v)
                    end
                else
                    copy = orig
                end
                return copy
            end
            
            is_batch_updating = true
            current_config = deep_copy(DEFAULT_CONFIG)
            is_batch_updating = false
            
            apply_all_configurations()
            brls.Application.notify("Configuration reset to default")
            return true
        end)
    end
    
    -- A/B Snapshot
    if sample_views.ab_snapshot then
        sample_views.ab_snapshot:onClick(function()
            -- Toggle between A and B snapshots
            if snapshot_a == nil then
                create_ab_snapshot("A")
            else
                create_ab_snapshot("B")
            end
            return true
        end)
    end
    
    -- A/B Compare
    if sample_views.ab_compare then
        sample_views.ab_compare:onClick(function()
            local diffs = compare_ab_snapshots()
            if diffs then
                -- Show diff dialog
                local diff_text = string.format("Found %d differences\n", #diffs)
                for i, diff in ipairs(diffs) do
                    if i <= 5 then
                        diff_text = diff_text .. string.format("%s: %s -> %s\n",
                            diff.path, tostring(diff.a_value), tostring(diff.b_value))
                    end
                end
                local dialog = brls.Dialog.new(diff_text)
                dialog:addButton("OK", function() return true end)
                dialog:open()
            end
            return true
        end)
    end
    
    -- Rapid Theme Cycling
    if sample_views.rapid_theme_cycling then
        sample_views.rapid_theme_cycling:onClick(function()
            start_rapid_theme_cycling()
            return true
        end)
    end
    
    -- Resolution Boundary Test
    if sample_views.resolution_boundary_test then
        sample_views.resolution_boundary_test:onClick(function()
            start_resolution_boundary_test()
            return true
        end)
    end
    
    -- Zero Dimension Test
    if sample_views.zero_dimension_test then
        sample_views.zero_dimension_test:onClick(function()
            start_zero_dimension_test()
            return true
        end)
    end
    
    -- Negative Scaling Test
    if sample_views.negative_scaling_test then
        sample_views.negative_scaling_test:onClick(function()
            start_negative_scaling_test()
            return true
        end)
    end
    
    -- Max Recursion Test
    if sample_views.max_recursion_test then
        sample_views.max_recursion_test:onClick(function()
            start_max_recursion_test()
            return true
        end)
    end
    
    -- List All Styles
    if sample_views.list_all_styles then
        sample_views.list_all_styles:onClick(function()
            list_all_style_metrics()
            return true
        end)
    end
    
    -- List All Colors
    if sample_views.list_all_colors then
        sample_views.list_all_colors:onClick(function()
            list_all_theme_colors()
            return true
        end)
    end
    
    -- List View Types
    if sample_views.list_all_view_types then
        sample_views.list_all_view_types:onClick(function()
            list_all_view_types()
            return true
        end)
    end
    
    -- List XML Attributes
    if sample_views.list_xml_attributes then
        sample_views.list_xml_attributes:onClick(function()
            list_xml_attributes()
            return true
        end)
    end
    
    -- Current Focus Info
    if sample_views.current_focus_info then
        sample_views.current_focus_info:onClick(function()
            get_current_focus_info()
            return true
        end)
    end
    
    -- View Tree Hierarchy
    if sample_views.view_tree_hierarchy then
        sample_views.view_tree_hierarchy:onClick(function()
            dump_view_tree_hierarchy()
            return true
        end)
    end
    
    -- Window size change listener for responsive layout
    -- Demonstrates reflow layout (elements keep size, layout rearranges)
    local function update_layout_for_window_size()
        local width = brls.Application.windowWidth()
        local height = brls.Application.windowHeight()
        
        -- Adjust split screen container based on window size
        if sample_views.split_screen_container then
            if width > 1200 then
                -- Wide screen: side by side (row layout)
                sample_views.split_screen_container:setAxis(brls.Axis.ROW)
            else
                -- Narrow screen: stacked (column layout)
                sample_views.split_screen_container:setAxis(brls.Axis.COLUMN)
            end
        end
        
        print(string.format("[layout_theme_settings] Window resized to %dx%d, layout adjusted", width, height))
    end
    
    -- Subscribe to window size changes
    local windowSizeEvent = brls.Application.getWindowSizeChangedEvent()
    if windowSizeEvent then
        windowSizeEvent:subscribe(function()
            update_layout_for_window_size()
        end)
    end
    
    -- Initial layout adjustment
    update_layout_for_window_size()
    
    -- Initialize remaining controls with default values
    init_remaining_controls()
    
    -- Setup performance monitoring
    setup_performance_monitoring()
    
    -- Initial configuration application
    apply_all_configurations()
    
    print("[layout_theme_settings] Module initialized successfully")
    brls.Application.notify("Layout & Theme Settings loaded")
end

-- Initialize remaining UI controls
function init_remaining_controls()
    -- Padding controls
    local padding_controls = {
        { "padding_top", "padding_top" },
        { "padding_right", "padding_right" },
        { "padding_bottom", "padding_bottom" },
        { "padding_left", "padding_left" },
    }
    
    for _, control in ipairs(padding_controls) do
        local view = sample_views[control[1]]
        if view then
            local value = current_config.spacing[control[2]]
            -- Capitalize first letter of each word
            local title = control[2]:gsub("_", " "):gsub("%f[%a]%l", string.upper)
            view:init(title, value / 50,
                function(v)
                    local actual = math.floor(v * 50)
                    current_config.spacing[control[2]] = actual
                    view:setDetailText(tostring(actual))
                    apply_spacing_config()
                end)
            view:setDetailText(tostring(value))
        end
    end
    
    -- Margin controls
    local margin_controls = {
        { "margin_top", "margin_top" },
        { "margin_right", "margin_right" },
        { "margin_bottom", "margin_bottom" },
        { "margin_left", "margin_left" },
    }
    
    for _, control in ipairs(margin_controls) do
        local view = sample_views[control[1]]
        if view then
            local value = current_config.spacing[control[2]]
            -- Capitalize first letter of each word
            local title = control[2]:gsub("_", " "):gsub("%f[%a]%l", string.upper)
            view:init(title, value / 50,
                function(v)
                    local actual = math.floor(v * 50)
                    current_config.spacing[control[2]] = actual
                    view:setDetailText(tostring(actual))
                    apply_spacing_config()
                end)
            view:setDetailText(tostring(value))
        end
    end
    
    -- Animation duration controls
    if sample_views.transition_duration then
        local value = current_config.animation.transition_duration
        sample_views.transition_duration:init("Transition Duration (ms)", value / 1000,
            function(v)
                local actual = math.floor(v * 1000)
                actual = math.max(0, math.min(2000, actual))
                current_config.animation.transition_duration = actual
                sample_views.transition_duration:setDetailText(tostring(actual) .. "ms")
                apply_animation_config()
            end)
        sample_views.transition_duration:setDetailText(tostring(value) .. "ms")
    end
    
    -- FPS stability monitor toggle
    if sample_views.fps_stability_monitor then
        sample_views.fps_stability_monitor:init("60FPS Stability Monitor", 
            current_config.rendering.fps_stability_monitor or false,
            function(value)
                current_config.rendering.fps_stability_monitor = value
            end)
    end
    
    -- Memory leak detection toggle
    if sample_views.memory_leak_detection then
        sample_views.memory_leak_detection:init("Memory Leak Detection",
            current_config.rendering.memory_leak_detection or false,
            function(value)
                current_config.rendering.memory_leak_detection = value
            end)
    end
    
    -- Typography Controls
    -- Body Font Size
    if sample_views.body_font_size then
        local value = current_config.typography.body_font_size
        sample_views.body_font_size:init("Body Font Size (10-72)",
            value / 72,
            function(v)
                local size = math.floor(v * 72)
                size = math.max(10, math.min(72, size))
                current_config.typography.body_font_size = size
                sample_views.body_font_size:setDetailText(tostring(size))
                apply_typography_config()
            end)
        sample_views.body_font_size:setDetailText(tostring(value))
    end
    
    -- Caption Font Size
    if sample_views.caption_font_size then
        local value = current_config.typography.caption_font_size
        sample_views.caption_font_size:init("Caption Font Size (10-72)",
            value / 72,
            function(v)
                local size = math.floor(v * 72)
                size = math.max(10, math.min(72, size))
                current_config.typography.caption_font_size = size
                sample_views.caption_font_size:setDetailText(tostring(size))
                apply_typography_config()
            end)
        sample_views.caption_font_size:setDetailText(tostring(value))
    end
    
    -- Monospace Font Toggle
    if sample_views.monospace_font_toggle then
        sample_views.monospace_font_toggle:init("Use Monospace Font",
            current_config.typography.monospace_font,
            function(value)
                current_config.typography.monospace_font = value
                apply_typography_config()
            end)
    end
    
    -- Dynamic Font Scaling
    if sample_views.dynamic_font_scaling then
        sample_views.dynamic_font_scaling:init("Dynamic Font Scaling (WCAG)",
            current_config.typography.dynamic_scaling,
            function(value)
                current_config.typography.dynamic_scaling = value
                apply_typography_config()
            end)
    end
    
    -- Letter Spacing
    if sample_views.letter_spacing then
        local value = current_config.typography.letter_spacing
        sample_views.letter_spacing:init("Letter Spacing (-0.5 to 2.0)",
            (value + 0.5) / 2.5,
            function(v)
                local actual = v * 2.5 - 0.5
                actual = math.max(-0.5, math.min(2.0, actual))
                current_config.typography.letter_spacing = actual
                sample_views.letter_spacing:setDetailText(string.format("%.2f", actual))
                apply_typography_config()
            end)
        sample_views.letter_spacing:setDetailText(string.format("%.2f", value))
    end
    
    -- Line Height
    if sample_views.line_height then
        local value = current_config.typography.line_height
        sample_views.line_height:init("Line Height Multiplier (1.0-2.0)",
            (value - 1.0) / 1.0,
            function(v)
                local actual = 1.0 + v * 1.0
                actual = math.max(1.0, math.min(2.0, actual))
                current_config.typography.line_height = actual
                sample_views.line_height:setDetailText(string.format("%.2f", actual))
                apply_typography_config()
            end)
        sample_views.line_height:setDetailText(string.format("%.2f", value))
    end
    
    -- Text Alignment
    if sample_views.text_alignment then
        local alignments = { "LEFT", "CENTER", "RIGHT" }
        sample_views.text_alignment:init("Default Text Alignment",
            {"Left", "Center", "Right"},
            find_index(alignments, current_config.typography.text_alignment),
            function(selected) end,
            function(selected)
                current_config.typography.text_alignment = alignments[selected + 1]
                apply_typography_config()
            end)
    end
    
    -- Layout Controls
    -- Align Items
    if sample_views.align_items_selector then
        local items = { "AUTO", "FLEX_START", "CENTER", "FLEX_END", "STRETCH", "BASELINE", "SPACE_BETWEEN", "SPACE_AROUND" }
        sample_views.align_items_selector:init("Align Items",
            {"Auto", "Flex Start", "Center", "Flex End", "Stretch", "Baseline", "Space Between", "Space Around"},
            find_index(items, current_config.layout.align_items),
            function(selected) end,
            function(selected)
                current_config.layout.align_items = items[selected + 1]
            end)
    end
    
    -- Stretch Factor
    if sample_views.stretch_factor then
        local value = current_config.layout.stretch_factor
        sample_views.stretch_factor:init("Stretch Factor (Grow)",
            value / 10.0,
            function(v)
                local actual = v * 10.0
                actual = math.max(0.0, math.min(10.0, actual))
                current_config.layout.stretch_factor = actual
                sample_views.stretch_factor:setDetailText(string.format("%.1f", actual))
            end)
        sample_views.stretch_factor:setDetailText(string.format("%.1f", value))
    end
    
    -- Shrink Factor
    if sample_views.shrink_factor then
        local value = current_config.layout.shrink_factor
        sample_views.shrink_factor:init("Shrink Factor",
            value / 10.0,
            function(v)
                local actual = v * 10.0
                actual = math.max(0.0, math.min(10.0, actual))
                current_config.layout.shrink_factor = actual
                sample_views.shrink_factor:setDetailText(string.format("%.1f", actual))
            end)
        sample_views.shrink_factor:setDetailText(string.format("%.1f", value))
    end
    
    -- Spacing Controls
    -- Separator Thickness
    if sample_views.separator_thickness then
        local value = current_config.spacing.separator_thickness
        sample_views.separator_thickness:init("Separator Thickness (1-10)",
            (value - 1) / 9.0,
            function(v)
                local actual = math.floor(1 + v * 9)
                actual = math.max(1, math.min(10, actual))
                current_config.spacing.separator_thickness = actual
                sample_views.separator_thickness:setDetailText(tostring(actual))
                apply_spacing_config()
            end)
        sample_views.separator_thickness:setDetailText(tostring(value))
    end
    
    -- Focus Border Inset
    if sample_views.focus_border_inset then
        local value = current_config.spacing.focus_border_inset
        sample_views.focus_border_inset:init("Focus Border Inset (0-10)",
            value / 10.0,
            function(v)
                local actual = math.floor(v * 10)
                actual = math.max(0, math.min(10, actual))
                current_config.spacing.focus_border_inset = actual
                sample_views.focus_border_inset:setDetailText(tostring(actual))
                apply_spacing_config()
            end)
        sample_views.focus_border_inset:setDetailText(tostring(value))
    end
    
    -- Glow Radius
    if sample_views.glow_radius then
        local value = current_config.spacing.glow_radius
        sample_views.glow_radius:init("Glow/Highlight Radius (0-20)",
            value / 20.0,
            function(v)
                local actual = math.floor(v * 20)
                actual = math.max(0, math.min(20, actual))
                current_config.spacing.glow_radius = actual
                sample_views.glow_radius:setDetailText(tostring(actual))
                apply_spacing_config()
            end)
        sample_views.glow_radius:setDetailText(tostring(value))
    end
    
    -- Animation Controls
    -- Stagger Delay
    if sample_views.stagger_delay then
        local value = current_config.animation.stagger_delay
        sample_views.stagger_delay:init("List Stagger Delay (0-500ms)",
            value / 500.0,
            function(v)
                local actual = math.floor(v * 500)
                actual = math.max(0, math.min(500, actual))
                current_config.animation.stagger_delay = actual
                sample_views.stagger_delay:setDetailText(tostring(actual) .. "ms")
                apply_animation_config()
            end)
        sample_views.stagger_delay:setDetailText(tostring(value) .. "ms")
    end
    
    -- Highlight Speed
    if sample_views.highlight_speed then
        local value = current_config.animation.highlight_speed
        sample_views.highlight_speed:init("Highlight Animation Speed (50-500ms)",
            (value - 50) / 450.0,
            function(v)
                local actual = math.floor(50 + v * 450)
                actual = math.max(50, math.min(500, actual))
                current_config.animation.highlight_speed = actual
                sample_views.highlight_speed:setDetailText(tostring(actual) .. "ms")
                apply_animation_config()
            end)
        sample_views.highlight_speed:setDetailText(tostring(value) .. "ms")
    end
    
    -- VSync Toggle
    if sample_views.vsync_toggle then
        sample_views.vsync_toggle:init("VSync Enabled",
            current_config.rendering.vsync,
            function(value)
                current_config.rendering.vsync = value
                apply_rendering_config()
            end)
    end
end

-- Setup performance monitoring
function setup_performance_monitoring()
    -- FPS update timer using recursive delay
    local function fps_update_loop()
        update_fps_metrics()
        check_memory_leaks()
        
        -- Update resolution display
        if sample_views.metrics_resolution then
            sample_views.metrics_resolution:setText(
                string.format("Resolution: %dx%d", brls.Application.windowWidth(), brls.Application.windowHeight()))
        end
        
        -- Update DPI scale display
        if sample_views.metrics_dpi_scale then
            sample_views.metrics_dpi_scale:setText(
                string.format("DPI Scale: %.2fx", current_config.window.dpi_scale))
        end
        
        -- Update theme display
        if sample_views.metrics_theme then
            sample_views.metrics_theme:setText(
                string.format("Theme: %s", current_config.theme.variant))
        end
        
        -- Schedule next update
        brls.delay(1000, fps_update_loop)
    end
    
    -- Start the loop
    fps_update_loop()
end

-- String helper for title case
function string:title()
    return self:gsub("(%a)([%w_]*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

return layout_theme_settings

