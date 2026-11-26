namespace Singularity.Apps.LedStudio {

    internal class LedIntents : Object {

        private static GLib.Settings? matrix() {
            var schema = SettingsSchemaSource.get_default().lookup("dev.sinty.desktop", true);
            if (schema == null || !schema.has_key("led-matrix-scene")) return null;
            return new GLib.Settings("dev.sinty.desktop");
        }

        private static GLib.Settings need_matrix() throws Error {
            var s = matrix();
            if (s == null) throw new IOError.NOT_SUPPORTED("this system has no LED matrix settings");
            return s;
        }

        private static string text(Json.Object args, string key) {
            return args.has_member(key) ? args.get_string_member(key).strip() : "";
        }

        private static string[] saved() {
            string[] out = {};
            try {
                var dir = Dir.open(LedScene.user_dir());
                string? name;
                while ((name = dir.read_name()) != null) {
                    if (name.has_suffix(".json")) out += name.substring(0, name.length - 5);
                }
            } catch (Error e) {
            }
            return out;
        }

        private static string stem_of(string name) {
            var b = new StringBuilder();
            foreach (var ch in name.down().to_utf8()) {
                if (ch.isalnum()) b.append_c(ch);
                else if (b.len > 0 && b.str[b.len - 1] != '-') b.append_c('-');
            }
            var s = b.str.strip();
            while (s.has_suffix("-")) s = s.substring(0, s.length - 1);
            return s != "" ? s : "scene";
        }

        private static void state(Json.Builder b, GLib.Settings m, string? before) {
            b.begin_object();
            b.set_member_name("enabled").add_boolean_value(m.get_boolean("led-matrix-enabled"));
            b.set_member_name("scene").add_string_value(m.get_string("led-matrix-scene"));
            b.set_member_name("brightness").add_int_value(m.get_int("led-matrix-brightness"));
            if (before != null) b.set_member_name("previous_scene").add_string_value(before);
            b.end_object();
        }

        private static string resolve(string scene) throws Error {
            if (scene == "") throw new IOError.INVALID_ARGUMENT("give a scene from led_scenes");
            foreach (var id in LedScene.builtin_ids()) if (id == scene) return id;
            var stem = scene.has_prefix("custom:") ? scene.substring(7) : scene;
            foreach (var s in saved()) if (s == stem) return "custom:" + s;
            throw new IOError.NOT_FOUND("no scene %s; see led_scenes", scene);
        }

        internal static void install(LedStudioApp app) {
            var agent = app.agent;
            agent.add_intent("led_scenes", "The LED matrix state and every scene it can show: the built-in ones and those saved in LED Studio.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    var b = new Json.Builder();
                    b.begin_object();
                    var m = matrix();
                    b.set_member_name("matrix");
                    if (m != null) state(b, m, null);
                    else b.add_null_value();
                    b.set_member_name("builtin").begin_array();
                    foreach (var id in LedScene.builtin_ids()) b.add_string_value(id);
                    b.end_array();
                    b.set_member_name("saved").begin_array();
                    foreach (var s in saved()) b.add_string_value("custom:" + s);
                    b.end_array();
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("led_show_text", "Write text on the LED matrix. It is saved as a scene and shown at once. The text may hold live values: {time}, {date}, {weekday}, {battery}, {cpu}, {memory}, {media}, {volume}, {notifications}. scroll is auto (only when too long), always or none.",
                "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"scroll\":{\"type\":\"string\",\"enum\":[\"auto\",\"always\",\"none\"]},\"brightness\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":7}},\"required\":[\"text\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var m = need_matrix();
                    var t = text(args, "text");
                    if (t == "") throw new IOError.INVALID_ARGUMENT("give the text to show");
                    var name = text(args, "name") != "" ? text(args, "name") : (t.char_count() > 24 ? t.substring(0, t.index_of_nth_char(24)) : t);
                    var s = new LedScene(name, 13, 8);
                    var l = new LedLayer.text_layer(t);
                    l.y = int.max((s.height - LedFont.HEIGHT) / 2, 0);
                    l.scroll = LedScroll.from_id(text(args, "scroll") != "" ? text(args, "scroll") : "auto");
                    if (args.has_member("brightness")) l.level = ((int) args.get_int_member("brightness")).clamp(0, 7);
                    s.layers.add(l);
                    var stem = stem_of(name);
                    s.save(Path.build_filename(LedScene.user_dir(), stem + ".json"));
                    var before = m.get_string("led-matrix-scene");
                    m.set_string("led-matrix-scene", "custom:" + stem);
                    m.set_boolean("led-matrix-enabled", true);
                    GLib.Settings.sync();
                    var b = new Json.Builder();
                    state(b, m, before);
                    return b.get_root();
                });
            agent.add_intent("led_use", "Show a scene on the LED matrix: a built-in id or custom:NAME from led_scenes.",
                "{\"type\":\"object\",\"properties\":{\"scene\":{\"type\":\"string\"}},\"required\":[\"scene\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var m = need_matrix();
                    var id = resolve(text(args, "scene"));
                    var before = m.get_string("led-matrix-scene");
                    m.set_string("led-matrix-scene", id);
                    m.set_boolean("led-matrix-enabled", true);
                    GLib.Settings.sync();
                    var b = new Json.Builder();
                    state(b, m, before);
                    return b.get_root();
                });
            agent.add_intent("led_matrix", "Turn the LED matrix on or off and set its brightness from 0 to 7.",
                "{\"type\":\"object\",\"properties\":{\"enabled\":{\"type\":\"boolean\"},\"brightness\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":7}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var m = need_matrix();
                    if (!args.has_member("enabled") && !args.has_member("brightness")) throw new IOError.INVALID_ARGUMENT("give enabled or brightness");
                    if (args.has_member("enabled")) m.set_boolean("led-matrix-enabled", args.get_boolean_member("enabled"));
                    if (args.has_member("brightness")) m.set_int("led-matrix-brightness", ((int) args.get_int_member("brightness")).clamp(0, 7));
                    GLib.Settings.sync();
                    var b = new Json.Builder();
                    state(b, m, null);
                    return b.get_root();
                });
        }
    }
}
