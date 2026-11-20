using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.LedStudio {

    public class LedStudioWindow : Singularity.Widgets.Window {
        public const int[] PRESET_SIZES = { 13, 8, 12, 8, 16, 16, 32, 8, 64, 32 };
        private const int[] ZOOM_STEPS = { 0, 8, 12, 16, 24, 32, 48, 64 };
        private const string[] SOURCES = { "{battery}", "{cpu}", "{memory}", "{media_progress}", "{volume}" };
        private const string[] DATA_KEYS = {
            "time", "date", "weekday", "battery", "charging", "cpu", "memory",
            "media", "media_progress", "playing", "volume", "notifications", "notification_count"
        };

        private AppSidebar sidebar;
        private Gee.HashMap<string, SidebarRow> rows = new Gee.HashMap<string, SidebarRow>();
        private LedStudioRibbon ribbon;
        private LedMatrixView view;
        private ScrolledWindow stage_scroll;
        private Button play_button;
        private Label position_label;
        private Label zoom_label;
        private Box frames_panel;
        private Box frames_list;
        private InspectorPanel inspector;
        private ToggleButton inspector_toggle;
        private Box properties_page;
        private ListBox layers_list;
        private Button layer_up;
        private Button layer_down;
        private Button layer_delete;
        private Button layer_duplicate;
        private SwitchRow live_clock;

        private LedScene scene;
        private LedContext ctx = new LedContext();
        private string current_id = "";
        private string? save_path = null;
        private int selected_layer = 0;
        private int current_frame = 0;
        private bool playing = true;
        private int64 started = 0;
        private uint tick_id = 0;
        private bool dirty = false;
        private bool syncing = false;
        private int paint_level = 7;
        private int zoom_index = 0;
        private LedDevice? device = null;
        private bool previewing = false;

        public static string preset_label(int width, int height) {
            if (width == 13 && height == 8) return _("Arduino UNO Q, 13 × 8");
            return "%d × %d".printf(width, height);
        }

        public LedStudioWindow(LedStudioApp app) {
            Object(application: app);
            set_default_size(1240, 780);
            seed_context();
            install_actions();

            sidebar = new AppSidebar(220);
            set_sidebar(sidebar);
            set_sidebar_visible(true);

            ribbon = new LedStudioRibbon();
            ribbon.level_chosen.connect((l) => paint_level = l);
            ribbon.duration_chosen.connect(set_frame_duration);
            ribbon.size_chosen.connect(resize);
            ribbon.color_chosen.connect((id) => {
                var c = Gdk.RGBA();
                c.parse(id);
                view.color = c;
                refresh_frames();
            });
            apply_view_edge(ribbon);

            var column = new Box(Orientation.VERTICAL, 0);
            column.hexpand = true;
            column.append(ribbon);
            column.append(build_center());
            var workspace = new Box(Orientation.HORIZONTAL, 0);
            workspace.append(column);
            workspace.append(build_inspector());
            set_content(workspace);

            ribbon.attach(this);
            add_bubble_icon("document-save-symbolic", _("Save (Ctrl+S)"), () => save());
            inspector_toggle = new ToggleButton();
            inspector_toggle.icon_name = "view-dual-symbolic";
            inspector_toggle.tooltip_text = _("Inspector (F4)");
            inspector_toggle.active = true;
            inspector_toggle.toggled.connect(() => inspector.visible = inspector_toggle.active);
            add_bubble_widget(inspector_toggle);
            add_bubble_suggested(_("Use on Matrix"), () => use_on_matrix());

            rebuild_sidebar();
            open_builtin("clock");
            tick_id = Timeout.add(40, tick);
            close_request.connect(() => {
                if (tick_id != 0) Source.remove(tick_id);
                tick_id = 0;
                stop_preview();
                return false;
            });
        }

        private void toast(string message) {
            add_toast(new Toast(message));
        }

        private void seed_context() {
            update_clock();
            ctx.set_value("battery", "76");
            ctx.set_value("charging", "1");
            ctx.set_value("cpu", "34");
            ctx.set_value("memory", "58");
            ctx.set_value("media", "Daft Punk - Veridis Quo");
            ctx.set_value("media_progress", "42");
            ctx.set_value("playing", "1");
            ctx.set_value("volume", "60");
            ctx.set_value("notifications", "Anna: dinner at eight?");
            ctx.set_value("notification_count", "2");
        }

        private void update_clock() {
            var now = new DateTime.now_local();
            ctx.set_value("time", now.format("%H:%M"));
            ctx.set_value("date", now.format("%d/%m"));
            ctx.set_value("weekday", now.format("%a"));
        }

        private Widget build_center() {
            var center = new Box(Orientation.VERTICAL, 0);
            center.hexpand = true;
            center.vexpand = true;
            center.add_css_class("ledstudio-center");

            view = new LedMatrixView();
            view.show_grid = true;
            view.padding = 24;
            view.paint.connect(on_paint);
            view.stroke_finished.connect(() => {
                mark_dirty();
                refresh_frames();
                refresh_layers();
            });
            stage_scroll = new ScrolledWindow();
            stage_scroll.vexpand = true;
            stage_scroll.child = view;
            stage_scroll.add_css_class("ledstudio-stage");
            var zoom_gesture = new EventControllerScroll(EventControllerScrollFlags.VERTICAL);
            zoom_gesture.scroll.connect((dx, dy) => {
                if ((zoom_gesture.get_current_event_state() & Gdk.ModifierType.CONTROL_MASK) == 0) return false;
                set_zoom(zoom_index + (dy < 0 ? 1 : -1));
                return true;
            });
            stage_scroll.add_controller(zoom_gesture);
            center.append(stage_scroll);

            var strip = new ControlStrip(6, 6);
            strip.margin_start = strip.margin_end = 12;
            strip.add_spacer();
            var back = strip.add_icon_button("media-skip-backward-symbolic", _("Previous Frame"));
            back.action_name = "win.prev-frame";
            play_button = strip.add_icon_button("media-playback-start-symbolic", _("Play or Pause (Space)"));
            play_button.action_name = "win.play-pause";
            var forward = strip.add_icon_button("media-skip-forward-symbolic", _("Next Frame"));
            forward.action_name = "win.next-frame";
            position_label = strip.add_numeric_label();
            strip.add_spacer();
            var out_btn = strip.add_icon_button("zoom-out-symbolic", _("Zoom Out (Ctrl+-)"));
            out_btn.action_name = "win.zoom-out";
            zoom_label = strip.add_numeric_label();
            var in_btn = strip.add_icon_button("zoom-in-symbolic", _("Zoom In (Ctrl++)"));
            in_btn.action_name = "win.zoom-in";
            var fit = strip.add_icon_button("zoom-fit-best-symbolic", _("Fit (Ctrl+0)"));
            fit.action_name = "win.zoom-fit";
            center.append(strip);

            frames_panel = new Box(Orientation.VERTICAL, 0);
            frames_panel.margin_start = frames_panel.margin_end = 12;
            frames_panel.margin_bottom = 10;
            frames_list = new Box(Orientation.HORIZONTAL, 4);
            frames_list.add_css_class("ledstudio-frames");
            var frames_scroll = new ScrolledWindow();
            frames_scroll.vscrollbar_policy = PolicyType.NEVER;
            frames_scroll.child = frames_list;
            frames_panel.append(frames_scroll);
            center.append(frames_panel);
            update_zoom_label();
            return center;
        }

        private Widget build_inspector() {
            inspector = new InspectorPanel(320);
            inspector.scroll_pages = true;
            inspector.compact_tabs = true;
            properties_page = new Box(Orientation.VERTICAL, 18);
            inspector.add_page("properties", _("Properties"), "document-properties-symbolic", properties_page, true);
            inspector.add_page("layers", _("Layers"), "view-list-symbolic", build_layers_page(), true);
            inspector.add_page("data", _("Test Data"), "utilities-system-monitor-symbolic", build_data_page(), true);
            inspector.page = "properties";
            return inspector;
        }

        private Button bar_button(string icon, string tooltip, string action) {
            var b = new Button.from_icon_name(icon);
            b.add_css_class("flat");
            b.tooltip_text = tooltip;
            b.action_name = "win." + action;
            b.update_property(AccessibleProperty.LABEL, tooltip, -1);
            return b;
        }

        private Widget build_layers_page() {
            var page = new Box(Orientation.VERTICAL, 6);
            layers_list = new ListBox();
            layers_list.add_css_class("ledstudio-layer-list");
            layers_list.selection_mode = SelectionMode.NONE;
            layers_list.activate_on_single_click = true;
            layers_list.row_activated.connect((r) => select_layer(scene.layers.length - 1 - r.get_index()));
            page.append(layers_list);
            var bar = new Box(Orientation.HORIZONTAL, 4);
            bar.add_css_class("ledstudio-layer-bar");
            var add = new MenuButton();
            add.icon_name = "list-add-symbolic";
            add.add_css_class("flat");
            add.tooltip_text = _("New Layer");
            var add_menu = new GLib.Menu();
            add_menu.append(_("Text"), "win.add-layer('text')");
            add_menu.append(_("Drawing"), "win.add-layer('bitmap')");
            add_menu.append(_("Bar"), "win.add-layer('bar')");
            add.menu_model = add_menu;
            bar.append(add);
            layer_duplicate = bar_button("edit-copy-symbolic", _("Duplicate"), "layer-duplicate");
            bar.append(layer_duplicate);
            layer_up = bar_button("go-up-symbolic", _("Move Up"), "layer-up");
            bar.append(layer_up);
            layer_down = bar_button("go-down-symbolic", _("Move Down"), "layer-down");
            bar.append(layer_down);
            var spacer = new Box(Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append(spacer);
            layer_delete = bar_button("user-trash-symbolic", _("Delete"), "layer-delete");
            bar.append(layer_delete);
            page.append(bar);
            return page;
        }

        private Widget build_data_page() {
            var page = new Box(Orientation.VERTICAL, 18);
            var clock = new PreferencesGroup(_("Clock"));
            live_clock = new SwitchRow(_("Live Clock"), _("Keep time and date current"), true);
            clock.add_row(live_clock);
            page.append(clock);
            var values = new PreferencesGroup(_("Values"), _("What the shell would provide to the scene"));
            foreach (unowned string key in DATA_KEYS) {
                var row = new EntryRow(key);
                row.text = ctx.get_value(key);
                string k = key;
                row.entry_changed.connect(() => {
                    if (k == "time" || k == "date" || k == "weekday") live_clock.active = false;
                    ctx.set_value(k, row.text);
                    refresh_layers();
                });
                values.add_row(row);
            }
            page.append(values);
            return page;
        }

        private delegate void Handler();

        private SimpleAction act(string name, owned Handler cb, string[]? accels = null) {
            var a = new SimpleAction(name, null);
            a.activate.connect(() => cb());
            add_action(a);
            if (accels != null) ((Gtk.Application) GLib.Application.get_default()).set_accels_for_action("win." + name, accels);
            return a;
        }

        private void stateful(string name, bool initial, owned Handler cb, string[]? accels = null) {
            var a = new SimpleAction.stateful(name, null, new Variant.boolean(initial));
            a.activate.connect(() => {
                a.set_state(new Variant.boolean(!a.get_state().get_boolean()));
                cb();
            });
            add_action(a);
            if (accels != null) ((Gtk.Application) GLib.Application.get_default()).set_accels_for_action("win." + name, accels);
        }

        private bool state_of(string name) {
            var a = lookup_action(name) as SimpleAction;
            return a != null && a.get_state().get_boolean();
        }

        private void set_state_of(string name, bool value) {
            var a = lookup_action(name) as SimpleAction;
            if (a != null) a.set_state(new Variant.boolean(value));
        }

        private void install_actions() {
            act("new", () => new_scene(), { "<Control>n" });
            act("import", () => choose_import(), { "<Control>o" });
            act("save", () => save(), { "<Control>s" });
            act("export", () => choose_export(), { "<Control><Shift>s" });
            act("revert", () => revert());
            act("use", () => use_on_matrix());
            act("play-pause", () => set_playing(!playing));
            act("prev-frame", () => step_frame(-1), { "comma" });
            act("next-frame", () => step_frame(1), { "period" });
            act("zoom-in", () => set_zoom(zoom_index + 1), { "<Control>plus", "<Control>equal" });
            act("zoom-out", () => set_zoom(zoom_index - 1), { "<Control>minus" });
            act("zoom-fit", () => set_zoom(0), { "<Control>0" });
            act("duplicate-frame", duplicate_frame);
            act("remove-frame", delete_frame);
            act("clear-frame", clear_frame);
            act("layer-up", () => move_layer(1));
            act("layer-down", () => move_layer(-1));
            act("layer-duplicate", duplicate_layer);
            act("layer-delete", delete_layer, { "Delete" });
            act("toggle-sidebar", () => set_sidebar_visible(!get_sidebar_visible()), { "F9" });
            act("toggle-inspector", () => inspector_toggle.active = !inspector_toggle.active, { "F4" });
            stateful("eraser", false, () => {}, { "e" });
            stateful("grid", true, () => view.show_grid = state_of("grid"));
            stateful("preview", false, () => {
                if (state_of("preview") != previewing) toggle_preview();
            });
            var add = new SimpleAction("add-layer", VariantType.STRING);
            add.activate.connect((v) => add_layer(LedLayerKind.from_id(v.get_string())));
            add_action(add);
        }

        private static string builtin_title(string id) {
            switch (id) {
                case "now-playing": return _("Now Playing");
                case "notifications": return _("Notifications");
                case "system": return _("System Load");
                case "battery": return _("Battery");
                default: return _("Clock");
            }
        }

        private static string builtin_icon(string id) {
            switch (id) {
                case "now-playing": return "audio-x-generic-symbolic";
                case "notifications": return "preferences-system-notifications-symbolic";
                case "system": return "utilities-system-monitor-symbolic";
                case "battery": return "battery-good-symbolic";
                default: return "preferences-system-time-symbolic";
            }
        }

        private string[] user_files() {
            string[] list = {};
            try {
                var dir = Dir.open(LedScene.user_dir());
                string? name;
                while ((name = dir.read_name()) != null) {
                    if (name.has_suffix(".json")) list += Path.build_filename(LedScene.user_dir(), name);
                }
            } catch (Error e) {
            }
            qsort_with_data<string>(list, sizeof(string), (a, b) => strcmp(a, b));
            return list;
        }

        private void rebuild_sidebar() {
            Widget? child;
            while ((child = sidebar.box.get_first_child()) != null) sidebar.box.remove(child);
            rows.clear();
            sidebar.box.append(new SidebarSectionLabel(_("Templates")));
            foreach (var id in LedScene.builtin_ids()) {
                var row = new SidebarRow(builtin_icon(id), builtin_title(id));
                string sid = id;
                row.clicked.connect(() => open_builtin(sid));
                rows["builtin:" + id] = row;
                sidebar.box.append(row);
            }
            sidebar.box.append(new SidebarSectionLabel(_("My Scenes")));
            foreach (var path in user_files()) {
                string label = Path.get_basename(path);
                label = label.substring(0, label.length - 5);
                try {
                    var s = LedScene.load(path);
                    if (s.name != "") label = s.name;
                } catch (Error e) {
                    continue;
                }
                var row = new SidebarRow("view-app-grid-symbolic", label);
                string p = path;
                row.clicked.connect(() => open_path(p));
                rows["file:" + path] = row;
                sidebar.box.append(row);
            }
            var add = new SidebarRow("list-add-symbolic", _("New Scene"));
            add.clicked.connect(() => new_scene());
            sidebar.box.append(add);
            mark_active();
        }

        private void mark_active() {
            foreach (var entry in rows.entries) entry.value.set_active(entry.key == current_id);
        }

        private void show_scene(LedScene s, string id, string? path) {
            scene = s;
            current_id = id;
            save_path = path;
            selected_layer = scene.layers.length - 1;
            current_frame = 0;
            started = get_monotonic_time();
            dirty = false;
            view.set_size(scene.width, scene.height);
            mark_active();
            refresh_all();
        }

        private void open_builtin(string id) {
            var s = LedScene.builtin(id, 13, 8);
            s.name = builtin_title(id);
            show_scene(s, "builtin:" + id, null);
            set_playing(true);
        }

        private void open_path(string path) {
            try {
                show_scene(LedScene.load(path), "file:" + path, path);
                set_playing(true);
            } catch (Error e) {
                toast(e.message);
            }
        }

        private void revert() {
            if (current_id.has_prefix("builtin:")) open_builtin(current_id.substring(8));
            else if (save_path != null) open_path(save_path);
        }

        private void new_scene() {
            int w = scene != null ? scene.width : 13;
            int h = scene != null ? scene.height : 8;
            var s = new LedScene(_("Untitled Scene"), w, h);
            var l = new LedLayer();
            l.kind = LedLayerKind.BITMAP;
            l.width = w;
            l.height = h;
            l.frames.add(new LedFrame(w, h));
            s.layers.add(l);
            show_scene(s, "", null);
            set_playing(false);
            ribbon.active_context = "draw";
        }

        public void import_file(File file) {
            if (file.get_path() == null) return;
            try {
                var s = LedScene.load(file.get_path());
                show_scene(s, "", null);
                dirty = true;
                refresh_title();
            } catch (Error e) {
                toast(_("Cannot open %s: %s").printf(file.get_basename(), e.message));
            }
        }

        private Gtk.FileFilter scene_filter() {
            var filter = new Gtk.FileFilter();
            filter.name = _("LED Scenes");
            filter.add_pattern("*.json");
            return filter;
        }

        private void choose_import() {
            var dialog = new Gtk.FileDialog();
            dialog.title = _("Import Scene");
            var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
            filters.append(scene_filter());
            dialog.filters = filters;
            dialog.open.begin(this, null, (obj, res) => {
                try {
                    import_file(dialog.open.end(res));
                } catch (Error e) {
                }
            });
        }

        private void choose_export() {
            var dialog = new Gtk.FileDialog();
            dialog.title = _("Export Scene");
            dialog.initial_name = file_stem() + ".json";
            var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
            filters.append(scene_filter());
            dialog.filters = filters;
            dialog.save.begin(this, null, (obj, res) => {
                try {
                    var file = dialog.save.end(res);
                    if (file != null && file.get_path() != null) {
                        scene.save(file.get_path());
                        toast(_("Exported to %s").printf(file.get_basename()));
                    }
                } catch (Error e) {
                    if (!(e is Gtk.DialogError)) toast(e.message);
                }
            });
        }

        private string file_stem() {
            string stem = scene.name.strip().down().replace("/", "-").replace(" ", "-");
            return stem == "" ? "scene" : stem;
        }

        private bool save() {
            if (save_path == null) {
                string target = Path.build_filename(LedScene.user_dir(), file_stem() + ".json");
                int n = 2;
                while (FileUtils.test(target, FileTest.EXISTS)) {
                    target = Path.build_filename(LedScene.user_dir(), "%s-%d.json".printf(file_stem(), n++));
                }
                save_path = target;
            }
            try {
                scene.save(save_path);
            } catch (Error e) {
                toast(e.message);
                return false;
            }
            current_id = "file:" + save_path;
            dirty = false;
            rebuild_sidebar();
            refresh_title();
            return true;
        }

        private void use_on_matrix() {
            if ((save_path == null || dirty) && !save()) return;
            string stem = Path.get_basename(save_path);
            stem = stem.substring(0, stem.length - 5);
            var schema = SettingsSchemaSource.get_default().lookup("dev.sinty.desktop", true);
            if (schema == null || !schema.has_key("led-matrix-scene")) {
                toast(_("Saved. This system has no LED matrix settings."));
                return;
            }
            var settings = new GLib.Settings("dev.sinty.desktop");
            settings.set_string("led-matrix-scene", "custom:" + stem);
            settings.set_boolean("led-matrix-enabled", true);
            toast(_("The matrix now shows “%s”").printf(scene.name));
        }

        private void toggle_preview() {
            if (previewing) {
                stop_preview();
                toast(_("The matrix is back to its own scene"));
                return;
            }
            device = LedDevice.open();
            if (device == null) {
                toast(_("The matrix is not answering"));
                set_state_of("preview", false);
                return;
            }
            device.lost.connect(() => {
                device = null;
                previewing = false;
                set_state_of("preview", false);
            });
            device.hold(true);
            previewing = true;
            set_state_of("preview", true);
            toast(_("Previewing on the matrix"));
        }

        private void stop_preview() {
            if (device != null) {
                device.hold(false);
                device.close();
            }
            device = null;
            previewing = false;
            set_state_of("preview", false);
        }

        private void set_zoom(int index) {
            zoom_index = index.clamp(0, ZOOM_STEPS.length - 1);
            view.cell_size = ZOOM_STEPS[zoom_index];
            stage_scroll.hscrollbar_policy = zoom_index == 0 ? PolicyType.NEVER : PolicyType.AUTOMATIC;
            stage_scroll.vscrollbar_policy = zoom_index == 0 ? PolicyType.NEVER : PolicyType.AUTOMATIC;
            update_zoom_label();
        }

        private void update_zoom_label() {
            zoom_label.label = zoom_index == 0 ? _("Fit") : _("%d px").printf(ZOOM_STEPS[zoom_index]);
        }

        private void set_playing(bool play) {
            playing = play;
            play_button.icon_name = play ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            view.editable = !play && current_bitmap() != null;
            if (play) started = get_monotonic_time();
            render();
        }

        private void step_frame(int delta) {
            var l = current_bitmap();
            set_playing(false);
            if (l == null) return;
            int n = (int) l.frames.length;
            current_frame = ((current_frame + delta) % n + n) % n;
            refresh_frames();
            render();
        }

        private bool tick() {
            if (live_clock.active) update_clock();
            if (playing) render();
            return Source.CONTINUE;
        }

        private void render() {
            if (scene == null) return;
            uint8[] px;
            var layer = current_bitmap();
            int64 ms = (get_monotonic_time() - started) / 1000;
            if (!playing && layer != null) {
                px = render_editing(layer);
                position_label.label = _("Frame %d of %u").printf(current_frame + 1, layer.frames.length);
            } else {
                px = LedRenderer.render(scene, ctx, ms);
                position_label.label = "%02d:%02d.%d".printf((int) (ms / 60000), (int) (ms / 1000 % 60), (int) (ms / 100 % 10));
            }
            view.set_pixels(px);
            if (previewing && device != null && device.width == scene.width && device.height == scene.height) device.frame(px);
        }

        private LedScene only(LedLayer layer, int frame) {
            var s = new LedScene(scene.name, scene.width, scene.height);
            var copy = layer.copy();
            copy.visible = true;
            copy.when = "";
            copy.blink_ms = 0;
            if (copy.kind == LedLayerKind.BITMAP && frame >= 0 && frame < copy.frames.length) {
                var f = copy.frames[frame];
                copy.frames = new GenericArray<LedFrame>();
                copy.frames.add(f);
            }
            s.layers.add(copy);
            return s;
        }

        private uint8[] render_editing(LedLayer editing) {
            var others = new LedScene(scene.name, scene.width, scene.height);
            for (int i = 0; i < scene.layers.length; i++) {
                if (i != selected_layer) others.layers.add(scene.layers[i]);
            }
            var px = LedRenderer.render(others, ctx, 0);
            var mine = LedRenderer.render(only(editing, current_frame), ctx, 0);
            for (int i = 0; i < px.length; i++) if (mine[i] > 0) px[i] = mine[i];
            return px;
        }

        private LedLayer? current_layer() {
            if (scene == null || selected_layer < 0 || selected_layer >= scene.layers.length) return null;
            return scene.layers[selected_layer];
        }

        private LedLayer? current_bitmap() {
            var l = current_layer();
            return l != null && l.kind == LedLayerKind.BITMAP && l.frames.length > 0 ? l : null;
        }

        private void on_paint(int x, int y, bool erase, bool first) {
            var l = current_bitmap();
            if (l == null) return;
            int lx = x - l.x, ly = y - l.y;
            if (lx < 0 || ly < 0 || lx >= l.width || ly >= l.height) return;
            var frame = l.frames[current_frame.clamp(0, (int) l.frames.length - 1)];
            frame.pixels[ly * l.width + lx] = erase || state_of("eraser") ? 0 : (uint8) paint_level;
            render();
        }

        private void mark_dirty() {
            if (!dirty) {
                dirty = true;
                refresh_title();
            }
        }

        private void refresh_all() {
            refresh_title();
            refresh_layers();
            refresh_properties();
            refresh_frames();
            set_playing(playing);
        }

        private void refresh_title() {
            set_title((dirty ? "• " : "") + scene.name);
            ribbon.size_selector.text = preset_label(scene.width, scene.height);
        }

        private void resize(int w, int h) {
            if (w == scene.width && h == scene.height) return;
            scene.width = w;
            scene.height = h;
            view.set_size(w, h);
            mark_dirty();
            refresh_all();
        }

        private static string kind_label(LedLayerKind kind) {
            switch (kind) {
                case LedLayerKind.BITMAP: return _("Drawing");
                case LedLayerKind.BAR: return _("Bar");
                default: return _("Text");
            }
        }

        private string layer_title(LedLayer l) {
            if (l.name != "") return l.name;
            if (l.kind == LedLayerKind.TEXT) return l.text;
            if (l.kind == LedLayerKind.BAR) return l.source;
            return kind_label(l.kind);
        }

        private LedMatrixView thumbnail(LedScene s, int max_width) {
            var t = new LedMatrixView();
            t.set_size(s.width, s.height);
            t.padding = 2;
            t.color = view.color;
            t.cell_size = int.max(1, max_width / s.width);
            t.hexpand = false;
            t.vexpand = false;
            t.can_target = false;
            t.set_pixels(LedRenderer.render(s, ctx, 0));
            return t;
        }

        private void refresh_layers() {
            Widget? child;
            while ((child = layers_list.get_first_child()) != null) layers_list.remove(child);
            for (int i = scene.layers.length - 1; i >= 0; i--) {
                var l = scene.layers[i];
                var row = new ListBoxRow();
                if (i == selected_layer) row.add_css_class("ledstudio-selected");
                var box = new Box(Orientation.HORIZONTAL, 8);
                box.margin_start = box.margin_end = 6;
                box.margin_top = box.margin_bottom = 4;
                box.append(thumbnail(only(l, 0), 48));
                var labels = new Box(Orientation.VERTICAL, 0);
                labels.hexpand = true;
                labels.valign = Align.CENTER;
                var name = new Label(layer_title(l));
                name.xalign = 0;
                name.ellipsize = Pango.EllipsizeMode.END;
                if (!l.visible) name.add_css_class("dim-label");
                var kind = new Label(kind_label(l.kind));
                kind.xalign = 0;
                kind.add_css_class("caption");
                kind.add_css_class("dim-label");
                labels.append(name);
                labels.append(kind);
                box.append(labels);
                var eye = new ToggleButton();
                eye.icon_name = l.visible ? "view-reveal-symbolic" : "view-conceal-symbolic";
                eye.active = l.visible;
                eye.add_css_class("flat");
                eye.add_css_class("ledstudio-layer-toggle");
                eye.valign = Align.CENTER;
                eye.tooltip_text = l.visible ? _("Hide") : _("Show");
                eye.toggled.connect(() => {
                    l.visible = eye.active;
                    eye.icon_name = l.visible ? "view-reveal-symbolic" : "view-conceal-symbolic";
                    eye.tooltip_text = l.visible ? _("Hide") : _("Show");
                    if (l.visible) name.remove_css_class("dim-label");
                    else name.add_css_class("dim-label");
                    mark_dirty();
                    render();
                });
                box.append(eye);
                row.child = box;
                layers_list.append(row);
            }
            bool has = current_layer() != null;
            layer_delete.sensitive = has;
            layer_duplicate.sensitive = has;
            layer_up.sensitive = has && selected_layer < scene.layers.length - 1;
            layer_down.sensitive = has && selected_layer > 0;
        }

        private void select_layer(int index) {
            selected_layer = index;
            current_frame = 0;
            refresh_layers();
            refresh_properties();
            refresh_frames();
            set_playing(playing);
        }

        private void add_layer(LedLayerKind kind) {
            var l = new LedLayer();
            l.kind = kind;
            switch (kind) {
                case LedLayerKind.TEXT:
                    l.text = _("Hello");
                    l.y = int.max((scene.height - LedFont.HEIGHT) / 2, 0);
                    break;
                case LedLayerKind.BITMAP:
                    l.width = scene.width;
                    l.height = scene.height;
                    l.frames.add(new LedFrame(scene.width, scene.height));
                    break;
                default:
                    l.source = "{battery}";
                    l.y = scene.height - 1;
                    l.height = 1;
                    break;
            }
            scene.layers.add(l);
            selected_layer = scene.layers.length - 1;
            current_frame = 0;
            mark_dirty();
            refresh_all();
            inspector.page = "properties";
            if (kind == LedLayerKind.BITMAP) {
                set_playing(false);
                ribbon.active_context = "draw";
            }
        }

        private void move_layer(int delta) {
            int to = selected_layer + delta;
            if (current_layer() == null || to < 0 || to >= scene.layers.length) return;
            var l = scene.layers[selected_layer];
            scene.layers.remove_index(selected_layer);
            scene.layers.insert(to, l);
            selected_layer = to;
            mark_dirty();
            refresh_layers();
            render();
        }

        private void duplicate_layer() {
            var l = current_layer();
            if (l == null) return;
            scene.layers.insert(selected_layer + 1, l.copy());
            selected_layer++;
            mark_dirty();
            refresh_all();
        }

        private void delete_layer() {
            if (current_layer() == null) return;
            scene.layers.remove_index(selected_layer);
            selected_layer = int.min(selected_layer, scene.layers.length - 1);
            current_frame = 0;
            mark_dirty();
            refresh_all();
        }

        private delegate void SetInt(int v);

        private SpinRow spin(string label, double min, double max, int value, owned SetInt apply) {
            var row = new SpinRow(label, null, min, max, 1, value);
            row.notify["value"].connect(() => {
                if (syncing) return;
                apply((int) row.value);
                mark_dirty();
                refresh_layers();
                render();
            });
            return row;
        }

        private void refresh_properties() {
            Widget? child;
            while ((child = properties_page.get_first_child()) != null) properties_page.remove(child);
            syncing = true;

            var scene_group = new PreferencesGroup(_("Scene"));
            var scene_name = new EntryRow(_("Name"));
            scene_name.text = scene.name;
            scene_name.entry_changed.connect(() => {
                scene.name = scene_name.text;
                mark_dirty();
                refresh_title();
            });
            scene_group.add_row(scene_name);
            properties_page.append(scene_group);

            var l = current_layer();
            if (l == null) {
                properties_page.append(InspectorPanel.empty_state("view-list-symbolic", _("No Layer"), _("Add text, a drawing or a bar from Insert")));
                syncing = false;
                return;
            }

            var content = new PreferencesGroup(kind_label(l.kind));
            var name = new EntryRow(_("Name"));
            name.text = l.name;
            name.placeholder_text = layer_title(l);
            name.entry_changed.connect(() => {
                l.name = name.text;
                mark_dirty();
                refresh_layers();
            });
            content.add_row(name);
            if (l.kind == LedLayerKind.TEXT) {
                var text = new EntryRow(_("Text"));
                text.text = l.text;
                text.entry_changed.connect(() => {
                    l.text = text.text;
                    mark_dirty();
                    refresh_layers();
                    render();
                });
                content.add_row(text);
                string[] scrolls = { _("When Too Long"), _("Always"), _("Never") };
                LedScroll[] scroll_values = { LedScroll.AUTO, LedScroll.ALWAYS, LedScroll.NONE };
                string current = scrolls[0];
                for (int i = 0; i < 3; i++) if (scroll_values[i] == l.scroll) current = scrolls[i];
                var scroll = new SelectionRow(_("Scroll"), scrolls, current);
                scroll.selected.connect((item) => {
                    for (int i = 0; i < 3; i++) if (scrolls[i] == item) l.scroll = scroll_values[i];
                    started = get_monotonic_time();
                    mark_dirty();
                });
                content.add_row(scroll);
                content.add_row(spin(_("Speed"), 1, 60, l.speed, (v) => l.speed = v));
                content.add_row(spin(_("Letter Spacing"), 0, 3, l.tracking, (v) => l.tracking = v));
            } else if (l.kind == LedLayerKind.BAR) {
                string[] items = SOURCES;
                if (!(l.source in items)) items += l.source;
                var source = new SelectionRow(_("Value"), items, l.source);
                source.selected.connect((item) => {
                    l.source = item;
                    mark_dirty();
                    refresh_layers();
                    render();
                });
                content.add_row(source);
                var vertical = new SwitchRow(_("Vertical"), null, l.vertical);
                vertical.switch_btn.notify["active"].connect(() => {
                    l.vertical = vertical.switch_btn.active;
                    mark_dirty();
                    render();
                });
                content.add_row(vertical);
            }
            properties_page.append(content);

            var place = new PreferencesGroup(_("Position"));
            place.add_row(spin(_("X"), -64, 64, l.x, (v) => l.x = v));
            place.add_row(spin(_("Y"), -64, 64, l.y, (v) => l.y = v));
            if (l.kind == LedLayerKind.BAR) {
                place.add_row(spin(_("Width"), 0, 64, l.width, (v) => l.width = v));
                place.add_row(spin(_("Height"), 0, 64, l.height, (v) => l.height = v));
            }
            properties_page.append(place);

            var look = new PreferencesGroup(_("Appearance"));
            look.add_row(spin(_("Brightness"), 1, 7, l.level, (v) => l.level = v));
            look.add_row(spin(_("Blink Every (ms)"), 0, 5000, l.blink_ms, (v) => l.blink_ms = v));
            var when = new EntryRow(_("Show Only When"));
            when.text = l.when;
            when.placeholder_text = "{charging}";
            when.entry_changed.connect(() => {
                l.when = when.text;
                mark_dirty();
                render();
            });
            look.add_row(when);
            properties_page.append(look);
            syncing = false;
        }

        private void refresh_frames() {
            Widget? child;
            while ((child = frames_list.get_first_child()) != null) frames_list.remove(child);
            var l = current_bitmap();
            frames_panel.visible = l != null;
            if (l == null) return;
            ribbon.duration_selector.text = _("%d ms").printf(l.frames[current_frame].duration_ms);
            for (int i = 0; i < l.frames.length; i++) {
                var button = new Button();
                button.add_css_class("flat");
                button.add_css_class("ledstudio-frame");
                if (i == current_frame) button.add_css_class("ledstudio-selected");
                var box = new Box(Orientation.VERTICAL, 2);
                box.append(thumbnail(only(l, i), 64));
                var label = new Label(_("%d ms").printf(l.frames[i].duration_ms));
                label.add_css_class("caption");
                label.add_css_class("dim-label");
                label.add_css_class("numeric");
                box.append(label);
                button.child = box;
                button.tooltip_text = _("Frame %d").printf(i + 1);
                int index = i;
                button.clicked.connect(() => {
                    current_frame = index;
                    set_playing(false);
                    refresh_frames();
                });
                frames_list.append(button);
            }
            var add = new Button.from_icon_name("list-add-symbolic");
            add.add_css_class("flat");
            add.add_css_class("ledstudio-frame");
            add.tooltip_text = _("Duplicate Frame");
            add.action_name = "win.duplicate-frame";
            frames_list.append(add);
        }

        private void set_frame_duration(int ms) {
            var l = current_bitmap();
            if (l == null) return;
            l.frames[current_frame].duration_ms = ms;
            mark_dirty();
            refresh_frames();
        }

        private void duplicate_frame() {
            var l = current_bitmap();
            if (l == null) return;
            l.frames.insert(current_frame + 1, l.frames[current_frame].copy());
            current_frame++;
            mark_dirty();
            set_playing(false);
            refresh_frames();
        }

        private void delete_frame() {
            var l = current_bitmap();
            if (l == null || l.frames.length < 2) return;
            l.frames.remove_index(current_frame);
            current_frame = int.min(current_frame, (int) l.frames.length - 1);
            mark_dirty();
            refresh_frames();
            render();
        }

        private void clear_frame() {
            var l = current_bitmap();
            if (l == null) return;
            var f = l.frames[current_frame];
            for (int i = 0; i < f.pixels.length; i++) f.pixels[i] = 0;
            mark_dirty();
            refresh_frames();
            render();
        }
    }
}
