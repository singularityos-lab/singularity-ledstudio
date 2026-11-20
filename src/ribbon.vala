using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.LedStudio {

    public class LedStudioRibbon : ContextRibbon {
        public RibbonSelector level_selector { get; private set; }
        public RibbonSelector duration_selector { get; private set; }
        public RibbonSelector size_selector { get; private set; }
        public RibbonSelector color_selector { get; private set; }

        public signal void level_chosen(int level);
        public signal void duration_chosen(int ms);
        public signal void size_chosen(int width, int height);
        public signal void color_chosen(string color);

        public LedStudioRibbon() {
            Object(orientation: Orientation.VERTICAL, spacing: 0, app_id: "dev.sinty.ledstudio");
            build_home(add_context("home", _("Home"), "go-home-symbolic"));
            build_insert(add_context("insert", _("Insert"), "list-add-symbolic"));
            build_draw(add_context("draw", _("Draw"), "applications-graphics-symbolic"));
            build_view(add_context("view", _("View"), "view-reveal-symbolic"));
        }

        private RibbonButton button(RibbonContext c, string icon, string label, string action, bool labelled = false, string? tip = null) {
            var b = c.add_button(icon, label, tip, "win." + action);
            b.label_in_compact = labelled;
            b.shortcut = accel_label(action);
            return b;
        }

        private RibbonToggle toggle(RibbonContext c, string icon, string label, string action, bool labelled = false) {
            var t = c.add_toggle(icon, label, null, "win." + action);
            t.label_in_compact = labelled;
            t.shortcut = accel_label(action);
            return t;
        }

        private static string? accel_label(string action) {
            var app = GLib.Application.get_default() as Gtk.Application;
            if (app == null) return null;
            string[] accels = app.get_accels_for_action("win." + action);
            if (accels.length == 0) return null;
            uint key;
            Gdk.ModifierType mods;
            if (!Gtk.accelerator_parse(accels[0], out key, out mods)) return null;
            return Gtk.accelerator_get_label(key, mods);
        }

        private void build_home(RibbonContext c) {
            button(c, "document-new-symbolic", _("New Scene"), "new");
            button(c, "document-open-symbolic", _("Import"), "import");
            button(c, "document-save-symbolic", _("Save"), "save");
            button(c, "document-save-as-symbolic", _("Export"), "export");
            c.add_separator();
            button(c, "edit-undo-symbolic", _("Revert"), "revert", false, _("Discard Unsaved Changes"));
            if (LedDevice.present()) {
                c.add_separator();
                toggle(c, "video-display-symbolic", _("Preview on Matrix"), "preview", true);
            }
        }

        private void build_insert(RibbonContext c) {
            button(c, "insert-text-symbolic", _("Text"), "add-layer('text')", true, _("Add a Text Layer"));
            button(c, "applications-graphics-symbolic", _("Drawing"), "add-layer('bitmap')", true, _("Add a Drawing Layer"));
            button(c, "view-continuous-symbolic", _("Bar"), "add-layer('bar')", true, _("Add a Bar Layer"));
        }

        private void build_draw(RibbonContext c) {
            toggle(c, "edit-clear-symbolic", _("Eraser"), "eraser", true);
            level_selector = c.add_selector(_("Pixel Brightness"), 8);
            for (int i = 7; i >= 1; i--) level_selector.add_option(i.to_string(), _("Level %d").printf(i));
            level_selector.text = _("Level %d").printf(7);
            level_selector.changed.connect((id) => level_chosen(int.parse(id)));
            c.add_separator();
            button(c, "edit-copy-symbolic", _("Duplicate Frame"), "duplicate-frame");
            button(c, "user-trash-symbolic", _("Remove Frame"), "remove-frame");
            button(c, "edit-clear-all-symbolic", _("Clear Frame"), "clear-frame");
            duration_selector = c.add_selector(_("Frame Duration"), 7);
            int[] durations = { 50, 100, 150, 250, 500, 1000, 2000 };
            foreach (int ms in durations) duration_selector.add_option(ms.to_string(), _("%d ms").printf(ms));
            duration_selector.changed.connect((id) => duration_chosen(int.parse(id)));
        }

        private void build_view(RibbonContext c) {
            size_selector = c.add_selector(_("Matrix Size"), 14);
            for (int i = 0; i + 1 < LedStudioWindow.PRESET_SIZES.length; i += 2) {
                int w = LedStudioWindow.PRESET_SIZES[i], h = LedStudioWindow.PRESET_SIZES[i + 1];
                size_selector.add_option("%dx%d".printf(w, h), LedStudioWindow.preset_label(w, h));
            }
            size_selector.changed.connect((id) => {
                var parts = id.split("x");
                size_chosen(int.parse(parts[0]), int.parse(parts[1]));
            });
            color_selector = c.add_selector(_("LED Color"), 7);
            color_selector.add_option("#ff5a3c", _("Red"));
            color_selector.add_option("#ffb02e", _("Amber"));
            color_selector.add_option("#39d353", _("Green"));
            color_selector.add_option("#3fa7ff", _("Blue"));
            color_selector.add_option("#f2f4f8", _("White"));
            color_selector.text = _("Red");
            color_selector.changed.connect((id) => color_chosen(id));
            c.add_separator();
            toggle(c, "view-grid-symbolic", _("Grid"), "grid");
        }
    }
}
