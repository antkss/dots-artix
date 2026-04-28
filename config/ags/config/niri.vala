using Json;
//public class NiriWorkspaceInfo : GLib.Object {
//    public int id;
//    public int idx;
//    public string? name;
//    public string output;
//    public bool is_urgent;
//    public bool is_active;
//    public bool is_focused;
//    public int active_window_id;
//
//    public NiriWorkspaceInfo(
//        int id,
//        int idx,
//        string? name,
//        string output,
//        bool is_urgent,
//        bool is_active,
//        bool is_focused,
//        int active_window_id
//    ) {
//        this.id = id;
//        this.idx = idx;
//        this.name = name;
//        this.output = output;
//        this.is_urgent = is_urgent;
//        this.is_active = is_active;
//        this.is_focused = is_focused;
//        this.active_window_id = active_window_id;
//    }
//}
//
//public class NiriWindowInfo : GLib.Object {
//    public int id;
//    public string? title;
//    public string? app_id;
//    public int workspace_id;
//    public bool is_focused;
//    public bool floating;
//    public bool is_urgent;
//
//    public NiriWindowInfo(
//        int id,
//        string? title,
//        string? app_id,
//        int workspace_id,
//        bool is_focused,
//        bool floating,
//        bool is_urgent
//    ) {
//        this.id = id;
//        this.title = title;
//        this.app_id = app_id;
//        this.workspace_id = workspace_id;
//        this.is_focused = is_focused;
//        this.floating = floating;
//        this.is_urgent = is_urgent;
//    }
//}
//
//public class NiriOutputInfo : GLib.Object {
//    public string name;
//    public int x;
//    public int y;
//    public int width;
//    public int height;
//
//    public NiriOutputInfo(string name, int x, int y, int width, int height) {
//        this.name = name;
//        this.x = x;
//        this.y = y;
//        this.width = width;
//        this.height = height;
//    }
//}
//
//public class NiriListener : GLib.Object {
//    public signal void changed();
//    public signal void workspaces_changed();
//    public signal void windows_changed();
//    public signal void outputs_changed();
//
//    public NiriWorkspaceInfo[] workspaces = {};
//    public NiriWindowInfo[] windows = {};
//    public NiriOutputInfo[] outputs = {};
//    public string focused_title = "";
//
//    private Pid event_pid = 0;
//    private IOChannel? event_channel = null;
//    private uint event_watch_id = 0;
//
//    public NiriListener() {
//        refresh_all();
//        start_event_stream();
//    }
//
//    ~NiriListener() {
//        stop_event_stream();
//    }
//
//    public void refresh_all() {
//        refresh_workspaces();
//        refresh_windows();
//        refresh_outputs();
//        changed();
//    }
//
//    public void refresh_workspaces() {
//        string output;
//        if (!run_command({"niri", "msg", "-j", "workspaces"}, out output))
//            return;
//
//        Json.Array? array = load_json_array(output);
//        if (array == null)
//            return;
//
//        NiriWorkspaceInfo[] items = {};
//        for (uint i = 0; i < array.get_length(); i++) {
//            var node = array.get_element(i);
//            if (node == null || node.get_node_type() != Json.NodeType.OBJECT)
//                continue;
//
//            var object = node.get_object();
//            items += new NiriWorkspaceInfo(
//                int_member(object, "id"),
//                int_member(object, "idx"),
//                string_member(object, "name"),
//                string_member(object, "output") ?? "",
//                bool_member(object, "is_urgent"),
//                bool_member(object, "is_active"),
//                bool_member(object, "is_focused"),
//                int_member(object, "active_window_id")
//            );
//        }
//
//        workspaces = items;
//        workspaces_changed();
//    }
//
//    public void refresh_windows() {
//        string output;
//        if (!run_command({"niri", "msg", "-j", "windows"}, out output))
//            return;
//
//        Json.Array? array = load_json_array(output);
//        if (array == null)
//            return;
//
//        NiriWindowInfo[] items = {};
//        string next_title = "";
//        for (uint i = 0; i < array.get_length(); i++) {
//            var node = array.get_element(i);
//            if (node == null || node.get_node_type() != Json.NodeType.OBJECT)
//                continue;
//
//            var object = node.get_object();
//            var window = new NiriWindowInfo(
//                int_member(object, "id"),
//                string_member(object, "title"),
//                string_member(object, "app_id"),
//                int_member(object, "workspace_id"),
//                bool_member(object, "is_focused"),
//                bool_member(object, "is_floating"),
//                bool_member(object, "is_urgent")
//            );
//            if (window.is_focused)
//                next_title = window.title ?? window.app_id ?? "";
//            items += window;
//        }
//
//        windows = items;
//        focused_title = next_title;
//        windows_changed();
//    }
//
//    public void refresh_outputs() {
//        string output;
//        if (!run_command({"niri", "msg", "-j", "outputs"}, out output))
//            return;
//
//        Json.Object? object = load_json_object(output);
//        if (object == null)
//            return;
//
//        NiriOutputInfo[] items = {};
//        foreach (unowned string member in object.get_members()) {
//            var output_node = object.get_member(member);
//            if (output_node == null || output_node.get_node_type() != Json.NodeType.OBJECT)
//                continue;
//
//            var output_object = output_node.get_object();
//            var logical_node = output_object.get_member("logical");
//            if (logical_node == null || logical_node.get_node_type() != Json.NodeType.OBJECT)
//                continue;
//
//            var logical = logical_node.get_object();
//            items += new NiriOutputInfo(
//                string_member(output_object, "name") ?? member,
//                int_member(logical, "x"),
//                int_member(logical, "y"),
//                int_member(logical, "width"),
//                int_member(logical, "height")
//            );
//        }
//
//        outputs = items;
//        outputs_changed();
//    }
//
//    private void start_event_stream() {
//        if (event_pid != 0)
//            return;
//
//        try {
//            int stdout_fd;
//            Process.spawn_async_with_pipes(
//                null,
//                {"niri", "msg", "event-stream"},
//                null,
//                SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
//                null,
//                out event_pid,
//                null,
//                out stdout_fd,
//                null
//            );
//
//            event_channel = new IOChannel.unix_new(stdout_fd);
//            event_watch_id = event_channel.add_watch(
//                IOCondition.IN | IOCondition.HUP | IOCondition.ERR,
//                on_event_stream
//            );
//
//            ChildWatch.add(event_pid, (pid, status) => {
//                stop_event_stream();
//                Timeout.add_seconds(1, () => {
//                    start_event_stream();
//                    return false;
//                });
//            });
//        } catch (SpawnError e) {
//            warning("Failed to start Niri event stream: %s", e.message);
//        }
//    }
//
//    private void stop_event_stream() {
//        if (event_watch_id != 0) {
//            Source.remove(event_watch_id);
//            event_watch_id = 0;
//        }
//
//        if (event_channel != null) {
//            try {
//                event_channel.shutdown(true);
//            } catch (IOChannelError e) {
//            }
//            event_channel = null;
//        }
//
//        if (event_pid != 0) {
//            Process.close_pid(event_pid);
//            event_pid = 0;
//        }
//    }
//
//    private bool on_event_stream(IOChannel source, IOCondition condition) {
//        if ((condition & (IOCondition.HUP | IOCondition.ERR)) != 0)
//            return false;
//
//        try {
//            string line;
//            size_t length;
//            size_t terminator_pos;
//            var status = source.read_line(out line, out length, out terminator_pos);
//            if (status == IOStatus.AGAIN)
//                return true;
//            if (status != IOStatus.NORMAL)
//                return false;
//
//            var text = line.strip();
//            if (text.has_prefix("Workspaces changed:")) {
//                refresh_workspaces();
//                refresh_windows();
//                changed();
//            } else if (text.has_prefix("Windows changed:")) {
//                refresh_windows();
//                refresh_workspaces();
//                changed();
//            } else if (text.has_prefix("Outputs changed:")) {
//                refresh_outputs();
//                changed();
//            } else if (text.has_prefix("Config loaded successfully")) {
//                refresh_all();
//            }
//
//            return true;
//        } catch (ConvertError e) {
//            warning("Failed to parse Niri event line: %s", e.message);
//            return false;
//        } catch (IOChannelError e) {
//            warning("Niri event stream closed: %s", e.message);
//            return false;
//        }
//    }
//
//    private bool run_command(string[] argv, out string standard_output) {
//        standard_output = "";
//        string standard_error = "";
//        int wait_status = 0;
//
//        try {
//            Process.spawn_sync(
//                null,
//                argv,
//                null,
//                SpawnFlags.SEARCH_PATH,
//                null,
//                out standard_output,
//                out standard_error,
//                out wait_status
//            );
//            Process.check_wait_status(wait_status);
//            return true;
//        } catch (Error e) {
//            warning("Niri command failed: %s", standard_error.strip() != "" ? standard_error.strip() : e.message);
//            return false;
//        }
//    }
//
//    private Json.Array? load_json_array(string json) {
//        try {
//            var parser = new Json.Parser();
//            parser.load_from_data(json, -1);
//            var root = parser.get_root();
//            if (root == null || root.get_node_type() != Json.NodeType.ARRAY)
//                return null;
//            return root.get_array();
//        } catch (Error e) {
//            warning("Failed to parse Niri JSON array: %s", e.message);
//            return null;
//        }
//    }
//
//    private Json.Object? load_json_object(string json) {
//        try {
//            var parser = new Json.Parser();
//            parser.load_from_data(json, -1);
//            var root = parser.get_root();
//            if (root == null || root.get_node_type() != Json.NodeType.OBJECT)
//                return null;
//            return root.get_object();
//        } catch (Error e) {
//            warning("Failed to parse Niri JSON object: %s", e.message);
//            return null;
//        }
//    }
//
//    private string? string_member(Json.Object object, string member) {
//        if (!object.has_member(member))
//            return null;
//
//        var node = object.get_member(member);
//        if (node == null || node.get_node_type() == Json.NodeType.NULL)
//            return null;
//
//        return object.get_string_member(member);
//    }
//
//    private int int_member(Json.Object object, string member) {
//        if (!object.has_member(member))
//            return 0;
//
//        return (int) object.get_int_member(member);
//    }
//
//    private bool bool_member(Json.Object object, string member) {
//        if (!object.has_member(member))
//            return false;
//
//        return object.get_boolean_member(member);
//    }
//}
public class NiriEventStream : GLib.Object {
    public signal void event_received(Json.Object json);
    public signal void disconnected();

    private static NiriEventStream? instance = null;

    private string socket_path;
    private GLib.Socket? socket;
    private GLib.DataInputStream? input;
    private bool running = false;

    public static NiriEventStream get_default() {
        if (instance == null) {
            instance = new NiriEventStream();
            instance.start(); // start only once
        }

        return instance;
    }

    private NiriEventStream() {
        socket_path = GLib.Environment.get_variable("NIRI_SOCKET") ?? "";

        if (socket_path == "") {
            warning("NIRI_SOCKET is not set");
        }
    }

    public void start() {
        if (running)
            return;

        if (socket_path == "") {
            warning("Cannot start Niri IPC stream: NIRI_SOCKET missing");
            return;
        }

        running = true;

        try {
            socket = new GLib.Socket(
                GLib.SocketFamily.UNIX,
                GLib.SocketType.STREAM,
                GLib.SocketProtocol.DEFAULT
            );

            socket.connect(new GLib.UnixSocketAddress(socket_path), null);

            string req = "\"EventStream\"\n";
            socket.send(req.data, null);

            var conn = GLib.SocketConnection.factory_create_connection(socket);
            input = new GLib.DataInputStream(conn.input_stream);

            read_loop.begin();

        } catch (Error e) {
            running = false;
            warning("Failed to connect to NIRI_SOCKET: %s", e.message);
        }
    }

    public void stop() {
        running = false;

        try {
            if (socket != null)
                socket.close();
        } catch (Error e) {
            warning("Failed to close Niri socket: %s", e.message);
        }

        socket = null;
        input = null;
    }

    private async void read_loop() {
        if (input == null)
            return;

        try {
            while (running) {
                size_t len = 0;

                string? line = yield input.read_line_async(
                    GLib.Priority.DEFAULT,
                    null,
                    out len
                );

                if (line == null)
                    break;
				
				var parser = new Json.Parser();
				parser.load_from_data(line, -1);
				Json.Object root = parser.get_root().get_object();
				if (root != null)
					event_received(root);
				else 
					print("malform niri ipc response ! \n");
            }
        } catch (Error e) {
            if (running)
                warning("Niri event stream error: %s", e.message);
        }

        running = false;
        disconnected();
    }
    public Json.Object? request(string request_json) {
        string socket_path = GLib.Environment.get_variable("NIRI_SOCKET") ?? "";

        if (socket_path == "") {
            warning("NIRI_SOCKET is not set");
            return null;
        }

        try {
            var socket = new GLib.Socket(
                GLib.SocketFamily.UNIX,
                GLib.SocketType.STREAM,
                GLib.SocketProtocol.DEFAULT
            );

            socket.connect(new GLib.UnixSocketAddress(socket_path), null);

            string request_line = request_json + "\n";
			//print(@"request_line: $request_line \n");
            socket.send(request_line.data, null);

            socket.shutdown(false, true);

            var conn = GLib.SocketConnection.factory_create_connection(socket);
            var input = new GLib.DataInputStream(conn.input_stream);

            size_t len = 0;
            string? reply = input.read_line(out len, null);

            socket.close();
			//print(@"json: $reply \n");

			if (reply != null) {
				var parser = new Json.Parser();
				parser.load_from_data(reply, -1);

				Json.Node root = parser.get_root();
				return root.get_object();
			}

        } catch (Error e) {
            warning("niri request_once failed: %s", e.message);
            return null;
        }
		return null;
    }
}
