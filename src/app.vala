using Gtk;

namespace Singularity.Apps.LedStudio {

    public class LedStudioApp : Singularity.Application, Singularity.Migration.Migratable, Singularity.Startup.Bootable {

        public LedStudioApp() {
            Object(application_id: "dev.sinty.ledstudio", flags: ApplicationFlags.HANDLES_OPEN);
        }

        protected override void startup() {
            base.startup();
            var provider = new CssProvider();
            provider.load_from_string(CSS);
            StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, STYLE_PROVIDER_PRIORITY_USER + 1);

            var menu = new GLib.Menu();
            var file_menu = new GLib.Menu();
            var file_new = new GLib.Menu();
            file_new.append(_("New Scene"), "win.new");
            file_new.append(_("Import Scene…"), "win.import");
            file_menu.append_section(null, file_new);
            var file_save = new GLib.Menu();
            file_save.append(_("Save"), "win.save");
            file_save.append(_("Export…"), "win.export");
            file_menu.append_section(null, file_save);
            var file_close = new GLib.Menu();
            file_close.append(_("Close Window"), "win.close");
            file_close.append(_("Quit"), "app.quit");
            file_menu.append_section(null, file_close);
            menu.append_submenu(_("File"), file_menu);
            var edit_menu = new GLib.Menu();
            edit_menu.append(_("Clear Frame"), "win.clear-frame");
            edit_menu.append(_("Use on Matrix"), "win.use");
            menu.append_submenu(_("Edit"), edit_menu);
            var view_menu = new GLib.Menu();
            view_menu.append(_("Play or Pause"), "win.play-pause");
            view_menu.append(_("Zoom In"), "win.zoom-in");
            view_menu.append(_("Zoom Out"), "win.zoom-out");
            view_menu.append(_("Fit"), "win.zoom-fit");
            view_menu.append(_("Toggle Inspector"), "win.toggle-inspector");
            view_menu.append(_("Toggle Sidebar"), "win.toggle-sidebar");
            menu.append_submenu(_("View"), view_menu);
            set_menubar(menu);

            var quit_action = new SimpleAction("quit", null);
            quit_action.activate.connect(() => quit());
            add_action(quit_action);
            set_accels_for_action("app.quit", { "<Control>q" });
            set_accels_for_action("win.close", { "<Control>w" });
        }

        private LedStudioWindow ensure_window() {
            var window = get_active_window() as LedStudioWindow;
            if (window == null) window = new LedStudioWindow(this);
            window.present();
            return window;
        }

        public Singularity.Startup.Plan build_plan(Singularity.Startup.Request request) {
            var plan = new Singularity.Startup.Plan();
            plan.version = "ledstudio-1";
            if (request.kind == Singularity.Startup.RequestKind.SERVICE) {
                plan.main("ready", Singularity.Startup.Category.PREPARE, (c) => {})
                    .reaches(Singularity.Startup.Milestone.SHELL_READY)
                    .reaches(Singularity.Startup.Milestone.CONTENT_READY)
                    .reaches(Singularity.Startup.Milestone.INTERACTIVE);
                return plan;
            }
            var shell = plan.main("window", Singularity.Startup.Category.SHELL, (c) => {
                c.window = ensure_window();
            }).reaches(Singularity.Startup.Milestone.SHELL_READY);
            if (request.kind == Singularity.Startup.RequestKind.OPEN) {
                var files = request.files();
                plan.main("open-file", Singularity.Startup.Category.CONTENT, (c) => open_files(files))
                    .depends_on("window")
                    .reaches(Singularity.Startup.Milestone.CONTENT_READY)
                    .reaches(Singularity.Startup.Milestone.INTERACTIVE);
            } else {
                shell.reaches(Singularity.Startup.Milestone.CONTENT_READY).reaches(Singularity.Startup.Milestone.INTERACTIVE);
            }
            return plan;
        }

        public void handle_request(Singularity.Startup.Request request) {
            if (request.kind == Singularity.Startup.RequestKind.OPEN) open_files(request.files());
            else ensure_window();
        }

        private void open_files(File[] files) {
            var window = ensure_window();
            foreach (var f in files) window.import_file(f);
        }

        public Variant save_model() {
            return new VariantDict().end();
        }

        public async void restore_model(Variant model) throws Error {
        }

        public string window_kind(Gtk.Window w) {
            return (w is LedStudioWindow) ? "studio" : "";
        }

        public Variant save_window(Gtk.Window w) {
            return ((LedStudioWindow) w).save_migration();
        }

        public string[] files() {
            string[] found = {};
            foreach (var w in get_windows()) {
                var studio = w as LedStudioWindow;
                if (studio == null) continue;
                foreach (var f in studio.migration_files()) {
                    if (!(f in found)) found += f;
                }
            }
            return found;
        }

        public void prepare_move() throws Singularity.Migration.MigrationError {
            foreach (var w in get_windows()) {
                var studio = w as LedStudioWindow;
                if (studio != null) studio.prepare_move();
            }
        }

        public async Gtk.Window? rebuild_window(string kind, Variant data) throws Error {
            if (kind != "studio") return null;
            var old = get_active_window() as LedStudioWindow;
            if (old != null) old.destroy();
            var w = new LedStudioWindow(this);
            w.restore_migration(data);
            return w;
        }

        private const string CSS = """
.sx-inspector {
    border-left: 1px solid alpha(@window_fg_color, 0.08);
}

.sx-inspector-header {
    margin: 0 14px 10px 14px;
}

.ledstudio-stage {
    background-color: #0d1015;
}

.ledstudio-frame {
    padding: 4px;
    border-radius: 8px;
}

.ledstudio-frame.ledstudio-selected,
.ledstudio-layer-list row.ledstudio-selected {
    background-color: alpha(@accent_bg_color, 0.22);
}

.ledstudio-layer-list {
    background: transparent;
}

.ledstudio-layer-list row {
    padding: 0;
    margin: 0 0 1px 0;
    border-radius: 8px;
    min-height: 0;
}

.ledstudio-layer-list row:hover {
    background-color: alpha(@window_fg_color, 0.05);
}

.ledstudio-layer-toggle {
    min-width: 24px;
    min-height: 24px;
    padding: 0;
    border-radius: 6px;
}

.ledstudio-layer-toggle:checked,
.ledstudio-layer-toggle:checked:hover {
    background: none;
    box-shadow: none;
}
""";
    }

    public static int main(string[] args) {
        Intl.setlocale(LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link("/proc/self/exe");
            locale_dir = Path.build_filename(Path.get_dirname(Path.get_dirname(exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain("singularity-ledstudio", locale_dir);
        Intl.bind_textdomain_codeset("singularity-ledstudio", "UTF-8");
        Intl.textdomain("singularity-ledstudio");
        Environment.set_application_name(_("LED Studio"));
        return new LedStudioApp().run(args);
    }
}
