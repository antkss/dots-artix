using GLib;
using Posix;
using GtkLayerShell;
public class Command : GLib.Object {
    private string[] command;
	public string output = "";
	public string error_msg = "";
    private GLib.Subprocess? _process;

    public Command(string[] command) {
        this.command = command;
    }
	public string get_output() {
		return output;
	}
	public string get_error() {
		return error_msg;
	}

    /// Synchronous spawn: blocks until command finishes.
    /// Suitable for short-lived commands that produce bounded output.
    public bool spawn_sync() {
        try {
            _process = new GLib.Subprocess.newv(
                command,
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
            );
            string? stdout_buf, stderr_buf;
            _process.communicate_utf8(null, null, out stdout_buf, out stderr_buf);
            if (stdout_buf != null) output = stdout_buf;
            if (stderr_buf != null) error_msg = stderr_buf;
            return _process.get_successful();
        } catch (GLib.Error e) {
            error_msg = e.message;
            return false;
        }
    }

    /// Async spawn: returns immediately, output available via signal or later read.
    public async bool spawn_async() {
        try {
            _process = new GLib.Subprocess.newv(
                command,
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
            );
            string? stdout_buf, stderr_buf;
            yield _process.communicate_utf8_async(null, null, out stdout_buf, out stderr_buf);
            if (stdout_buf != null) output = stdout_buf;
            if (stderr_buf != null) error_msg = stderr_buf;
            return _process.get_successful();
        } catch (GLib.Error e) {
            error_msg = e.message;
            return false;
        }
    }

    /// Forcefully terminates the process (SIGKILL).
    public void kill() {
        if (_process != null) {
            _process.force_exit();
            _process = null;
        }
    }

    // Legacy alias — kept for any external callers that still reference .spawn()
    public GLib.Pid spawn() {
        spawn_sync();
        return 0;
    }
}
public void widget_set_class_names(Gtk.Widget widget, string[] class_names) {
	for (int i = 0; i < class_names.length; i++) {
		widget.get_style_context().add_class(class_names[i]);
	}
}
private class Css {
    private static HashTable<Gtk.Widget, Gtk.CssProvider> _providers;
    public static HashTable<Gtk.Widget, Gtk.CssProvider> providers {
        get {
            if (_providers == null) {
                _providers = new HashTable<Gtk.Widget, Gtk.CssProvider>(
                    (w) => (uint)w,
                    (a, b) => a == b);
            }

            return _providers;
        }
    }
}
public void remove_provider(Gtk.Widget widget) {
    var providers = Css.providers;

    if (providers.contains(widget)) {
        var p = providers.get(widget);
        widget.get_style_context().remove_provider(p);
        providers.remove(widget);
        p.dispose();
    }
}
public void widget_set_css(Gtk.Widget widget, string css) {
    var providers = Css.providers;

    if (providers.contains(widget)) {
        remove_provider(widget);
    } else {
        widget.destroy.connect(() => {
            remove_provider(widget);
        });
    }

    var style = !css.contains("{") || !css.contains("}")
        ? "* { ".concat(css, "}") : css;

    var p = new Gtk.CssProvider();
    widget.get_style_context()
        .add_provider(p, Gtk.STYLE_PROVIDER_PRIORITY_USER);

    try {
        p.load_from_data(style, style.length);
        providers.set(widget, p);
    } catch (GLib.Error err) {
        warning(err.message);
    }
}
public string force_fit(string text, int limit) {
    // 🔵 Get the actual character count (handles UTF-8 correctly)
	if (text == null) 
		return string.nfill(limit, ' ');
    long char_count = text.char_count();

    if (char_count > limit) {
        // ✂️ TRUNCATE: Cut it at the limit
        // We find the byte offset of the 'limit' character
        long byte_index = text.index_of_nth_char(limit);
        return text.substring(0, (long)byte_index); // Optional: Remove "..." if you want strict cut
    } 
    else {
        // 🧱 PAD: Add spaces to fill the void
        string spaces = string.nfill((long)(limit - char_count), ' ');
        return text + spaces;
    }
}
public class WiggleSeekbar : Gtk.DrawingArea {
    // 📊 State: Just one number (0.0 = Empty, 1.0 = Full)
    public double percent { get; private set; default = 0.0; }

    // 🌊 Visual Settings
    public double amplitude = 3.0;
    public double frequency = 0.4;
    public double phase = 0.0;
	public double width = 2.0;
	public double circle_radius = 4.0;

    // 📡 Signal: Emits the new percentage (0.0 to 1.0) when clicked
    public signal void on_percent_change(double p);
	public bool playing = true;

    public WiggleSeekbar() {
        //this.set_size_request(200, 10);
		this.hexpand = true;
        this.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.POINTER_MOTION_MASK);

        // Animation Loop
        Timeout.add(16, () => {
			if (this.playing) {
				this.phase += 0.05; 
				this.queue_draw();
			}
            return true;
        });

        this.draw.connect((ctx) => {
            int w = this.get_allocated_width();
            int h = this.get_allocated_height();
            double mid_y = h / 2.0;
            
            // 🟢 DIRECT: Use the percent directly to find the split point
            double split_x = w * this.percent; 

            // Style: Thinner and Lighter
            ctx.set_line_width(this.width);
            ctx.set_line_cap(Cairo.LineCap.ROUND);
			var style_context = this.get_style_context();
			var fg_color = style_context.get_color(style_context.get_state());
            // 1. Unplayed Line
            //ctx.set_source_rgba(0.3, 0.3, 0.3, 0.5);
			ctx.set_source_rgba(fg_color.red, fg_color.green, fg_color.blue, 0.3);
            ctx.move_to(split_x, mid_y);
            ctx.line_to(w, mid_y);
            ctx.stroke();

            // 2. Played Wiggle
            //ctx.set_source_rgba(0.8, 0.6, 1.0, 0.8);
			Gdk.cairo_set_source_rgba(ctx, fg_color);
            ctx.move_to(0, mid_y);
			double end_y = mid_y;
            for (double x = 0; x <= split_x; x++) {
                double y = mid_y + (amplitude * Math.sin((x * frequency) + phase));
                ctx.line_to(x, y);
				end_y = y;
            }
            ctx.stroke();
			ctx.move_to(split_x, end_y);
			circle_here(ctx, this.circle_radius);
            return true;
        });

        // Input
        this.button_press_event.connect((e) => { handle_input(e.x); return true; });
        this.motion_notify_event.connect((e) => {
            if ((e.state & Gdk.ModifierType.BUTTON1_MASK) != 0) handle_input(e.x);
            return true;
        });
    }
	public static void circle_here(Cairo.Context ctx, double radius) {
        double x, y;
        ctx.get_current_point(out x, out y);
        ctx.new_sub_path();
        ctx.arc(x, y, radius, 0, 2 * Math.PI);
        ctx.fill();
        ctx.move_to(x, y);
    }
    // 🟢 SETTER: Call this with 0.5 for 50%, 0.75 for 75%, etc.
    public void set_progress(double p) {
        this.percent = p.clamp(0.0, 1.0);
        this.queue_draw();
    }

    private void handle_input(double mouse_x) {
        int w = this.get_allocated_width();
        
        // Calculate new percentage based on click position
        double new_p = (mouse_x / w).clamp(0.0, 1.0);
        
        // Emit signal so main app knows
        this.on_percent_change(new_p);
        
        // Update visual immediately
        this.set_progress(new_p);
    }
}


class Workspaces : Gtk.Box {
    // GLib.HashTable<int, string> icons = new GLib.HashTable<int,string>(GLib.direct_hash,GLib.direct_equal);
    AstalHyprland.Hyprland? hypr = AstalHyprland.get_default();
	NiriEventStream? niri = NiriEventStream.get_default();
	public signal void niri_focus(int64 id, bool focused);
    public Workspaces() {

		//icons.set(1, ""); 
		//icons.set(2, ""); 
		//icons.set(3, ""); 
		//icons.set(4, ""); 
		//icons.set(5, ""); 
		//icons.set(6, ""); 
		//icons.set(7, ""); 
		//icons.set(8, ""); 
		//icons.set(9,"");
		if (hypr != null) {
			hypr.notify["workspaces"].connect(sync);
			sync();
		} else {
			sync_niri();
		}


    }
	void sync_niri() {
		niri.event_received.connect((obj)=> {
			Json.Node? node_wsc = obj.get_member("WorkspacesChanged");
			Json.Node? node_fa = obj.get_member("WorkspaceActivated");
			if (node_wsc != null) {
				Json.Object root = node_wsc.get_object();
				Json.Array? wsp_arr = root.get_member("workspaces").get_array();
				if (wsp_arr != null) {
					foreach (var child in get_children())
						child.destroy();
					for (int i = 0; i < wsp_arr.get_length(); i++) {
						Json.Object ws = wsp_arr.get_object_element(i);
						int64 id = ws.get_int_member("id");
						int64 idx = ws.get_int_member("idx");
						//string output = ws.get_string_member("output");
						//bool is_urgent = ws.get_boolean_member("is_urgent");
						bool is_active = ws.get_boolean_member("is_active");
						bool is_focused = ws.get_boolean_member("is_focused");
						// debug
						//print("workspace id=%lld idx=%lld output=%s focused=%s active=%s\n",
						//	  id,
						//	  idx,
						//	  output,
						//	  is_focused.to_string(),
						//	  is_active.to_string());
						add(button_ws(id, idx, is_focused, is_active));
					}
				} else {
					print("malform niri output ! \n");
				}
			} else if (node_fa != null) {
				Json.Object root = node_fa.get_object();
				int64 id = root.get_int_member("id");
				bool focused = root.get_boolean_member("focused");
				niri_focus(id, focused);
			}
		});
	}

    void sync() {
        foreach (var child in get_children())
            child.destroy();

        foreach (var ws in hypr.workspaces)
            add(button(ws));
    }
    Gtk.Button button_ws(int64 id, int64 idx, bool is_focus, bool is_active) {
		string icon = idx.to_string("%d");
		if (idx < 0){
		  icon = "";
		}
		var btn = new Gtk.Button() {
			visible = true,
			label = icon
		};
		var context = btn.get_style_context();
		if (is_active) {
			context.add_class("button_active");
		} else {
			context.remove_class("button_active");
			context.add_class("button");
		}
		ulong niri_handler_id = 0;
		niri_handler_id = this.niri_focus.connect((focus_id, focused) => {
				bool active_now = focus_id == id;
				if (active_now) {
					context.add_class("button_active");
				} else {
					context.remove_class("button_active");
					context.add_class("button");
				}
		});
		btn.destroy.connect(() => {
			if (niri_handler_id > 0)
				this.disconnect(niri_handler_id);
		});

		btn.clicked.connect(()=> {
			Command action = new Command({"niri", "msg", "action", "focus-workspace", idx.to_string()});
			action.spawn_sync();
		});
        return btn;
    }
    Gtk.Button button(AstalHyprland.Workspace ws) {
	// string icon = icons.lookup(ws.id);
	string icon = ws.id.to_string("%d");
	// if (icon == null){
	//   icon = ws.id.to_string();
	// }
	if (ws.id < 0){
	  icon = "";
	}
	var btn = new Gtk.Button() {
		visible = true,
		label = icon
	};
	var focused = hypr.focused_workspace == ws;
	var context = btn.get_style_context();
	if (focused ) {
	    context.add_class("button_active");
	} else {
		context.remove_class("button_active");
	    context.add_class("button");
	}
	ulong hypr_handler_id = 0;
	hypr_handler_id = hypr.notify["focused-workspace"].connect(() => {
	    focused = hypr.focused_workspace == ws;
            if (focused) {
                context.add_class("button_active");
            } else {
				context.remove_class("button_active");
                context.add_class("button");
            }
        });
        btn.destroy.connect(() => {
            if (hypr_handler_id > 0)
                hypr.disconnect(hypr_handler_id);
        });

        // btn.clicked.connect(ws.focus);
        return btn;
    }
}

class FocusedClient : Gtk.Box {
	Gtk.Label label = new Gtk.Label("") { visible = true };
	AstalHyprland.Hyprland? hypr = AstalHyprland.get_default();
	NiriEventStream? niri = NiriEventStream.get_default();
	string get_title(int64 wid) {
		string title = "";
		Json.Object obj = niri.request("\"Windows\"");
		if (obj != null) {
			//print("obj ready ! \n");
			Json.Object winobjs = obj.get_member("Ok").get_object();
			Json.Array? windows = winobjs.get_member("Windows").get_array();
			//print(@"length: $(windows.get_length())");
			for (int i = 0; i < windows.get_length(); i++) {
				Json.Object w = windows.get_object_element(i);
				int64 cur_id = w.get_int_member("id");
				if (cur_id == wid) {
					title = w.get_string_member("title");
					break;
				}
			}
		} else {
			print("malform niri ipc response ! \n");
		}
		return title;
	}
    public FocusedClient() {
		widget_set_class_names(this.label,{"text"});
		this.label.set_xalign(0.0f);
		this.label.set_ellipsize(Pango.EllipsizeMode.END);
		this.label.set_max_width_chars(60);
		add(this.label);
		if (hypr != null) {
			hypr.notify["focused-client"].connect(sync_clients);
			//AstalHyprland.get_default().notify.connect((sender, param_spec) => {
			//	// 🟢 This prints ANY property that changes on the player
			//	print(@"Property changed: $(param_spec.name)\n");
			//	//print("%s \n", this.main_player.metadata.print(true));
			//});

		} else if (niri != null){
			niri.event_received.connect((obj)=> {
				Json.Node fcc = obj.get_member("WindowFocusChanged");
				if (fcc != null) {
					Json.Object root = fcc.get_object();
					string title = get_title(root.get_int_member("id"));
					//print(@"title: $title \n");
					if (title != null) {
						this.label.set_text(title);
					} else {
						this.label.set_text("");
					}
				}


			});
		}

    }

    void sync_clients() {
        var client = this.hypr.focused_client;
        if (client == null)
            return;
		var title = client.title;
		if (title != null) {
			this.label.set_text(title);
		} else {
			this.label.set_text("");
		}

    }
}
public class TrayMenu : Gtk.Window {
    public Gtk.Box menu_box;
    private Gtk.Fixed fixed_layout;
	public string? home = Environment.get_variable("HOME");
	public signal void on_space_click();
	public void init_css() {
		try {
			var provider = new Gtk.CssProvider();
			provider.load_from_file(GLib.File.new_for_path(home + "/.config/ags/" + "style.css"));
			Gtk.StyleContext.add_provider_for_screen(
				Gdk.Screen.get_default(),
				provider,
				Gtk.STYLE_PROVIDER_PRIORITY_USER
			);
		} catch {
			print("Can't load css, an error occur !");
		}

    }

	public void add_to_tray(Gtk.Widget widget) {
		this.menu_box.add(widget);
	}
	public void destroy_all_child() {
		foreach (var child in this.menu_box.get_children())
            child.destroy();
	}
	public uint get_child_idx(Gtk.Widget widget) {
		return this.menu_box.get_children().index(widget);
	}
    public TrayMenu(Gdk.Monitor mon) {
	// 1. Initialize Layer Shell
        GtkLayerShell.init_for_window(this);

        // 2. anchor: TOP | BOTTOM | LEFT | RIGHT (Full Screen)
        // ➡️ Sets the window to cover the entire screen area
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);

        // ➡️ Places the window above everything, including full-screen apps
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);

        // ➡️ Allows the window to take keyboard focus when needed
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND);

        // 5. Visual Setup
        // ➡️ Since it covers the whole screen, you usually want it transparent
        this.set_app_paintable(true);
        var visual = this.get_screen().get_rgba_visual();
        if (visual != null) {
            this.set_visual(visual);
        }
        
		init_css();
		widget_set_css(this, "background: transparent;");
		this.key_press_event.connect((event) => {
			switch (event.keyval) {
				case Gdk.Key.Up:
					this.menu_box.child_focus(Gtk.DirectionType.TAB_BACKWARD);
					return true; // "I handled this, stop processing"
				case Gdk.Key.Down:
					this.menu_box.child_focus(Gtk.DirectionType.TAB_FORWARD);
					return true;
				case Gdk.Key.Tab:
					this.menu_box.child_focus(Gtk.DirectionType.TAB_FORWARD);
					return true;
				case Gdk.Key.Return:
				case Gdk.Key.KP_Enter: // Numpad Enter
				case Gdk.Key.space:    // Spacebar (Standard accessibility behavior)
					this.on_space_click();
					
					// 1. Get the currently focused widget
					var focused_widget = this.get_focus();

					// 2. Check if it is actually a Button
					if (focused_widget is Gtk.Button) {
						// 3. Force it to behave as if clicked
						// This runs the code inside your btn.clicked.connect(...)
						var btn = focused_widget as Gtk.Button;
						if (btn != null) {
							btn.clicked();
						}
					}
					return true; // Stop event
				case Gdk.Key.Escape:
					this.hide();
					return true;
				//default:
				//	this.hide();
				//	return true;
			}
			return true;

		});
		//this.notify.connect((a, b)=> {
		//	print(@"name: $(b.name) \n");
		//});
		this.focus_out_event.connect(()=>{
			this.hide();
			return true;
		});

		this.button_press_event.connect((e) => {
			// 🛑 1. Filter out Double/Triple Clicks
			// If we don't do this, fast clicks on children bubble up and close us!
			if (e.type == Gdk.EventType.2BUTTON_PRESS || e.type == Gdk.EventType.3BUTTON_PRESS) {
				return true; // "Eat" the event, but do NOT hide
			}

			// 🟢 2. Normal Logic (Single Click on background)
			this.hide();
			return true; 
		});
        // 4. 🟢 HANDLE CLICK OUTSIDE (Clicking the curtain)
        // Events on the window itself = Close
        //this.button_press_event.connect(() => {
        //    this.hide();
        //    return true; // Stop propagation
        //});

        // 5. Layout Container (Fixed allows manual X/Y positioning)
        fixed_layout = new Gtk.Fixed();
        add(fixed_layout);

        // 6. The Actual Menu Box
        menu_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        
        // Style the MENU BOX (Not the window)
        menu_box.get_style_context().add_class("tray-menu"); // Apply your dark CSS here
        
        fixed_layout.put(menu_box, 0, 0);
    }

    public void toggle_at_widget(Gtk.Widget target) {
        if (this.is_visible()) {
            this.hide();
        } else {
            // 1. Calculate Coordinates (Same as before)
            var toplevel = target.get_toplevel();
            if (toplevel.is_toplevel()) {
                int win_x, win_y;
                toplevel.get_window().get_origin(out win_x, out win_y);

                int btn_x, btn_y;
                target.translate_coordinates(toplevel, 0, 0, out btn_x, out btn_y);

                int final_x = win_x + btn_x;
                int final_y = win_y + btn_y;

                // 2. 🟢 MOVE THE BOX (Not the window)
                // We move the box inside the fixed layout
                fixed_layout.move(menu_box, final_x, final_y);

                this.show_all();
                this.present();
            }
        }
    }
}
//Gtk.Button buttonT(AstalMpris.Player player) {
//	var btn = new Gtk.Button() {
//		visible = true,
//		label = player.playback_status == 0 ? "": ""
//	};
//
//	widget_set_class_names(btn, {"button_active"});
//	btn.clicked.connect(() => {
//
//	});
//	return btn;
//}
class LabelBtn: Gtk.Button {
	public Gtk.Label my_label = new Gtk.Label("");
	public LabelBtn(string? str) {
		this.get_style_context().add_class("button_inactive");
		my_label.set_label(str ?? "");
		add(my_label);
	}
}
class BigBtn: Gtk.Button {
	public BigBtn(string ?str="") {
		set_label(str);
		this.get_style_context().add_class("button_big");
	}
}
class ActiveBtn: Gtk.Button {
	public ActiveBtn(string ?str = "") {
		set_label(str);
		set_hexpand(false);
		set_vexpand(false);
		widget_set_class_names(this, {"button_active_big"});
	}
}
class LabelPanel: Gtk.Label {
	public LabelPanel(string ?str) {
		widget_set_class_names(this, { "button_panel"});
		set_text(str);
	}
}
class ButtonPanel: Gtk.Button {
	public ButtonPanel(string ?str) {
		set_label(str);
		widget_set_class_names(this, {"button_panel"});
	}
}
class Media : Gtk.Box {
    AstalMpris.Mpris mpris = AstalMpris.get_default();
	Gtk.Button play_button = new Gtk.Button() { visible = true };
	Gtk.Label play_label = new Gtk.Label("♫ Nothing Playing ♫") { visible = true };
	AstalMpris.Player main_player = null;
	public GLib.List<weak AstalMpris.Player> players = null;
	Gtk.Button menu_btn;
    TrayMenu tray_menu_media; // 1. Define the menu
	// Track signal handler IDs to prevent accumulation
	private ulong title_handler_id = 0;
	private ulong playback_status_handler_id = 0;
	//uint chosen_player = 0;
	//public GLib.List <Gtk.Label> menu_tray_labels = null;
    public Media(Gdk.Monitor mon) {
		widget_set_class_names(this.play_button, { "button_active" });
		widget_set_class_names(play_label, {"space"});
		play_label.set_ellipsize(Pango.EllipsizeMode.END);
		play_label.set_max_width_chars(45);
		//this.mpris.player_closed.connect(() => {
		//	print("player disappeared ! \n");
		//});
        mpris.notify["players"].connect(sync_players);

		this.play_button.clicked.connect(() => {
			if (this.main_player != null) {
				this.main_player.play_pause();
			}
		});

		//this.mpris.notify.connect((sender, param_spec) => {
		//	// 🟢 This prints ANY property that changes on the player
		//	print(@"Property changed: $(param_spec.name)\n");
		//});
		this.play_button.set_label("");
		tray_menu_media = new TrayMenu(mon);
		this.tray_menu_media.add_to_tray(new LabelPanel("* Nothing here *"));
		this.tray_menu_media.on_space_click.connect((event)=>{
			if (this.main_player != null) {
				this.main_player.play_pause();
			}
		});
        menu_btn = new Gtk.Button();
		widget_set_class_names(menu_btn, { "button" });
		menu_btn.set_label("↓");
        menu_btn.clicked.connect(() => {
            // Pass the button itself so the menu knows where to appear
            tray_menu_media.toggle_at_widget(menu_btn);
        });
        add(menu_btn);
		add(play_button);
		add(play_label);
    }
	void on_playback_status() {
		if (this.main_player != null) {
			var title = this.main_player.title;
			this.play_label.set_label(@"♫ $title");
			if (this.main_player.playback_status == 0) {
				this.play_button.set_label("");
			} else {
				this.play_button.set_label("");
			}
		}
	}
	void change_players() {
		if (this.main_player != null) {
			// Disconnect old handler to prevent accumulation
			if (playback_status_handler_id > 0) {
				this.main_player.disconnect(playback_status_handler_id);
			}
			playback_status_handler_id = this.main_player.notify["playback-status"].connect(on_playback_status);
			var title = this.main_player.title;
			this.play_label.set_label(@"♫ $title");
			if (this.main_player.playback_status == 0) {
				this.play_button.set_label("");
			} else {
				this.play_button.set_label("");
			}
		}
	}
    void sync_players() {
		print("players changed ! \n");
		this.tray_menu_media.hide();
		this.tray_menu_media.destroy_all_child();
        if (mpris.players.length() < 1) {
			//this.my_tray_menu.add_to_tray(this.play_label);
			this.tray_menu_media.add_to_tray(new LabelBtn("* Nothing here *"));
			this.play_button.set_label("");
			this.play_label.set_label("♫ Nothing Playing ♫");
			this.players = null;
			this.main_player = null;
            return;
        }
		this.players = this.mpris.players.copy();
		if (this.main_player == null || this.players.find(this.main_player) == null) {
			this.main_player = this.players.nth_data(0);
			// Disconnect old handler to prevent accumulation
			if (title_handler_id > 0) {
				this.main_player.disconnect(title_handler_id);
			}
			title_handler_id = this.main_player.notify["title"].connect(()=>{
				this.play_label.set_text(@"♫ $(this.main_player.title)");
			});
		} 
		//if (chosen_player >= this.players.length()) {
		//	chosen_player = this.players.length() - 1;
		//}

		//this.menu_tray_labels = null;
		//int i = 0;
		foreach(var player in this.players) {
			//player.notify.connect((a, b)=>{
			//	if (b.name != "position")
			//		print(@"changed: $(b.name) \n");
			//});
			//int box_idx = i;
			var line = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			var music_icon = new Gtk.Button();
			//var title = player.title;
			var label = new Gtk.Label("");
			//var label_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			var prev_btn = new ActiveBtn("󰒮");
			var pause_btn = new ActiveBtn("");
			var next_btn = new ActiveBtn("󰒭");
			var upper_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			var lower_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			//var btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			//var ver_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			var control_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			//var padding_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			var seekbar = new WiggleSeekbar();
			if (!tray_menu_media.is_visible()) {
				seekbar.playing = false;
			}
			//widget_set_css(seekbar, "all: unset; min-width: 200px;");
            // 2. Put the scaled pixbuf into the Image widget
			//icon.set_size_request(100, 100);
			//if (player.cover_art != null) {int limit
			//	icon.set_from_file(player.cover_art);
			//} else {
			//}
			//icon.set_from_icon_name("library-music", Gtk.IconSize.DIALOG);
			//widget_set_class_names(icon, {"music_icon"});
			//label.set_xalign(0.0f);
			//label.set_ellipsize(Pango.EllipsizeMode.END);
			//label.set_max_width_chars(60);
			label.xalign = 0; 
			label.max_width_chars = 200;
			//label.width_chars = 30;
			label.ellipsize = Pango.EllipsizeMode.END;
			label.set_text(@"♫ $(player.title)");
			widget_set_class_names(music_icon, { "music_icon" });
			widget_set_class_names(line, { "music_icon" });
			widget_set_class_names(label, { "space" });
			widget_set_class_names(lower_box, { "bar" });
			widget_set_css(lower_box, "margin: 4px;");
			widget_set_css(pause_btn, "margin-left: 4px;");
			widget_set_css(next_btn, "margin-left: 4px;");
			widget_set_css(prev_btn, "margin-left: 4px;");
			//widget_set_css(padding_box, "all:unset; min-height: 50px;");
			//widget_set_css(seekbar, @"all: unset; min-width: 200px;");
			line.set_data<AstalMpris.Player>("player", player);
			//line.set_data<Gtk.Label>("label", label);
			line.can_focus = true;
			prev_btn.can_focus = false;
			pause_btn.can_focus = false;
			next_btn.can_focus = false;
			music_icon.can_focus = false;
			upper_box.add(music_icon);
			upper_box.add(label);
			lower_box.add(seekbar);
			lower_box.add(control_box);
			line.add(upper_box);
			line.add(lower_box);
			control_box.add(prev_btn);
			control_box.add(pause_btn);
			control_box.add(next_btn);
			if (player.length > 0)
				seekbar.set_progress(player.position / player.length);
			else
				seekbar.set_progress(0);

			music_icon.clicked.connect(()=> {
				line.grab_focus();
			});
			seekbar.on_percent_change.connect((position)=> {
				player.position = player.length * position;
			});
			if (player.playback_status != 0) {
				pause_btn.set_label("");
			} else {
				pause_btn.set_label("");
			}
			//player.notify["metadata"].connect(()=> {
			//	print(@"metadata: $(player.metadata.print(true)) \n");
			//});
			player.notify["position"].connect((a, b)=>{
				//print(@"percent: $(player.position / player.length) \n");
				if (player.position >= 0 && player.length > 0) {
					seekbar.set_progress(player.position / player.length);
				} else {
					seekbar.set_progress(0);
				}
				if (tray_menu_media.is_visible()) {
					seekbar.playing = true;
				} else {
					seekbar.playing = false;
				}
			});
			prev_btn.clicked.connect(()=>{
				player.previous();
			});
			pause_btn.clicked.connect(()=>{
				player.play_pause();
			});

			player.notify["playback-status"].connect((a, b)=> {
				seekbar.playing = false;
				if (player.playback_status != 0) {
					pause_btn.set_label("");
				} else {
					pause_btn.set_label("");
				}
			});
			next_btn.clicked.connect(()=>{
				player.next();
			});
			//line.add(label);
			//line.add(pause_btn);

			player.notify["cover-art"].connect(() => {
				widget_set_css(music_icon, @"background-image: url(\"file://$(player.cover_art)\");background-position: center;");
				//widget_set_css(music_icon, "background-size: cover;");
			});
			player.notify["title"].connect(()=>{
				label.set_text(@"♫ $(player.title)");
			});
			widget_set_css(music_icon, @"background-image: url(\"file://$(player.cover_art)\");background-position: center;");
			//widget_set_css(music_icon, "background-position: center;");
			//widget_set_css(music_icon, "background-size: cover;");
			//line.event.connect((a, b)=> {
			//	print(@"name: $(a.name) \n");
			//	return true;
			//});
			line.focus_in_event.connect(() => {
				//this.chosen_player = box_idx;
				var candidate = line.get_data<AstalMpris.Player>("player");
				if (this.main_player == candidate) {
					print("same player ! \n");
				} else {
					this.main_player = candidate;
				}
				change_players();
				return true;
			});
			this.tray_menu_media.add_to_tray(line);
		}

		change_players();

    }
}


class SysTray : Gtk.Box {
    HashTable<string, Gtk.Widget> items = new HashTable<string, Gtk.Widget>(str_hash, str_equal);
    AstalTray.Tray tray = AstalTray.get_default();

    public SysTray() {
        widget_set_class_names(this, { "SysTray" });
        tray.item_added.connect(add_item);
        tray.item_removed.connect(remove_item);
    }

    void add_item(string id) {
        if (items.contains(id))
            return;
        var item = tray.get_item(id);
        var btn = new Gtk.MenuButton() { use_popover = false, visible = true };
        var icon = new Astal.Icon() { visible = true };
        item.bind_property("tooltip-markup", btn, "tooltip-markup", BindingFlags.SYNC_CREATE);
        item.bind_property("gicon", icon, "gicon", BindingFlags.SYNC_CREATE);
        item.bind_property("menu-model", btn, "menu-model", BindingFlags.SYNC_CREATE);
		widget_set_class_names(btn, {"button"});
        btn.insert_action_group("dbusmenu", item.action_group);
        item.notify["action-group"].connect(() => {
            btn.insert_action_group("dbusmenu", item.action_group);
        });

        btn.add(icon);
        add(btn);
        items.set(id, btn);
    }

    void remove_item(string id) {
        if (items.contains(id)) {
			items.lookup(id).destroy();
            items.remove(id);
        }
    }
}
class Wifi : Astal.Icon {
    public Wifi() {
        widget_set_class_names(this, {"Wifi"});
        var wifi = AstalNetwork.get_default();
        wifi.wifi.bind_property("ssid", this, "tooltip-text", BindingFlags.SYNC_CREATE);
        wifi.wifi.bind_property("icon-name", this, "icon", BindingFlags.SYNC_CREATE);
    }
}
public string[] get_subfolders(string path) {
    string[] folders = {};
    File dir = File.new_for_path(path);

    try {
        // 🔹 Start enumerating children
        FileEnumerator enumerator = dir.enumerate_children(
            "standard::*", 
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, 
            null
        );

        FileInfo info;
        while ((info = enumerator.next_file(null)) != null) {
            // 🔸 Check if item is strictly a directory
            if (info.get_file_type() != FileType.REGULAR) {
                // 📥 Add to array
                folders += info.get_name();
            }
        }
    } catch (GLib.Error e) {
		print("Error: %s \n", e.message);
    }

    return folders;
}

public class VolumeWatcher : GLib.Object {
    public signal void volume_changed(double volume_percent, bool muted);

    private GLib.Subprocess? monitor_proc;
    private GLib.DataInputStream? monitor_stream;
    private uint refresh_timeout_id = 0;

    /// Public: read the last known volume (0-100) and mute state.
    public double current_volume { get; private set; default = -1; }
    public bool current_muted { get; private set; default = false; }

    public VolumeWatcher() {
        start_monitor();
        // Do an initial synchronous read so current_volume is available immediately
        refresh_volume();
    }

    ~VolumeWatcher() {
        if (monitor_proc != null) {
            monitor_proc.force_exit();
        }
    }

    public void set_volume(double percent) {
        percent = percent.clamp(0.0, 100.0);

        try {
            string vol = "%.0f%%".printf(percent);

            var proc = new GLib.Subprocess.newv(
                { "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", vol },
                GLib.SubprocessFlags.STDERR_SILENCE
            );

            proc.wait(null);
        } catch (GLib.Error e) {
            warning("set_volume failed: %s", e.message);
        }
    }

    private void start_monitor() {
        try {
            monitor_proc = new GLib.Subprocess.newv(
                { "pw-dump", "-m" },
                GLib.SubprocessFlags.STDOUT_PIPE |
                GLib.SubprocessFlags.STDERR_SILENCE
            );

            monitor_stream = new GLib.DataInputStream(
                monitor_proc.get_stdout_pipe()
            );

            read_monitor_loop.begin();
        } catch (GLib.Error e) {
            warning("failed to start pw-dump -m: %s", e.message);
        }
    }

    private async void read_monitor_loop() {
        if (monitor_stream == null)
            return;

        try {
            while (true) {
                size_t len = 0;
                string? line = yield monitor_stream.read_line_async(
                    GLib.Priority.DEFAULT,
                    null,
                    out len
                );

                if (line == null)
                    break;

                // pw-dump -m can print many lines per event, so debounce refresh.
                queue_refresh();
            }
        } catch (GLib.Error e) {
            warning("pw-dump monitor read failed: %s", e.message);
        }
    }

    private void queue_refresh() {
        if (refresh_timeout_id != 0)
            return;

        refresh_timeout_id = GLib.Timeout.add(80, () => {
            refresh_timeout_id = 0;
            refresh_volume();
            return GLib.Source.REMOVE;
        });
    }

    private void refresh_volume() {
        try {
            string? stdout_buf;
            string? stderr_buf;

            var proc = new GLib.Subprocess.newv(
                { "wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@" },
                GLib.SubprocessFlags.STDOUT_PIPE |
                GLib.SubprocessFlags.STDERR_SILENCE
            );

            proc.communicate_utf8(null, null, out stdout_buf, out stderr_buf);

            if (!proc.get_successful() || stdout_buf == null)
                return;

            // Example:
            // Volume: 0.45
            // Volume: 0.45 [MUTED]
            bool muted = stdout_buf.index_of("[MUTED]") >= 0;

            var re = new GLib.Regex("""Volume:\s*([0-9.]+)""");
            GLib.MatchInfo match;

            if (!re.match(stdout_buf, 0, out match))
                return;

            double linear = double.parse(match.fetch(1));
            double percent = linear * 100.0;

            if (Math.fabs(percent - current_volume) > 0.5 || muted != current_muted) {
                current_volume = percent;
                current_muted = muted;
                volume_changed(percent, muted);
            }
        } catch (GLib.Error e) {
            warning("refresh_volume failed: %s", e.message);
        }
    }
}
public class BrightnessWatcher : GLib.Object {
    // 🟢 1. Define the Signal (The Callback)
    // We send a double (0.0 to 100.0) so it works easily with Sliders
    public signal void brightness_changed(double percentage);

    private FileMonitor monitor;
    private File file;
    
    // Paths
    private string path_dir = "/sys/class/backlight/";
    private string path_brightness;
    private string path_max;
    public double max_level = 1.0;

    public BrightnessWatcher() {
		var backlight = get_subfolders(path_dir);
		//foreach (var path in backlight) {
		//	print("%s \n", path);
		//}
		if (backlight != null && backlight.length > 0) {
			this.path_brightness = GLib.Path.build_filename(path_dir, backlight[0] ,"brightness");
			this.path_max = GLib.Path.build_filename(path_dir, backlight[0], "max_brightness");

			// 1. Read Max Brightness first (needed for math)
			read_max_level();

			// 2. Setup Monitor
			this.file = File.new_for_path(path_brightness);
			try {
				this.monitor = file.monitor_file(FileMonitorFlags.NONE, null);
				this.monitor.changed.connect((src, dest, event_type) => {
					if (event_type == FileMonitorEvent.CHANGED || 
						event_type == FileMonitorEvent.CHANGES_DONE_HINT) {
						read_current_level();
					}
				});

				// Initial read
				read_current_level();
			} catch (GLib.Error e) {
				warning("Error monitoring file: %s", e.message);
			}
		} else {
			print("No backlight found !");
		}
		brightness_changed(get_brightness());

    }
	public void set_brightness(double percentage) {
		if (this.path_brightness != null) {
			// 1. Safety Checks (Clamp 0-100)
			if (percentage < 1) percentage = 1;
			if (percentage > 100) percentage = 100;

			// 2. Calculate Raw Integer (e.g., 50% of 96000 = 48000)
			int target_val = (int)((percentage / 100.0) * this.max_level);

			// 3. Write to file
			try {
				FileUtils.set_contents(this.path_brightness, target_val.to_string());
			} catch (GLib.Error e) {
				print("Write to %s failed: %s\n", this.path_brightness, e.message);
			}
		} else {
			print("No backlight found !");
		}

    }

    public void read_max_level() {
		if (this.path_max != null) {
			try {
				string content;
				if (FileUtils.get_contents(path_max, out content)) {
					this.max_level = double.parse(content.strip());
				}
			} catch (GLib.Error e) {
				warning("Could not read max_brightness: %s", e.message);
			}
		} else {
			print("No backlight found !");
		}
    }

    public void read_current_level() {
		if (this.path_brightness != null) {
			try {
				string content;
				if (FileUtils.get_contents(path_brightness, out content)) {
					double current = double.parse(content.strip());
					
					// Calculate Percentage
					double percent = (current / this.max_level) * 100.0;
					//print(@"brightness: $percent \n");

					// 🟢 3. Emit the signal (Trigger the callback)
					brightness_changed(percent);
				}
			} catch (GLib.Error e) {
				warning("Read error: %s", e.message);
			}
		} else {
			print("No backlight found !");
		}
    }
	public double get_brightness() {
		if (this.path_brightness != null) {
			try {
				string content;
				if (FileUtils.get_contents(path_brightness, out content)) {
					double current = double.parse(content.strip());
					double percent = (current / this.max_level) * 100.0;
					return percent;
				}
			} catch (GLib.Error e) {
				warning("Read error: %s", e.message);
			}
		} else {
			print("No backlight found !");
		}

		return 1.0;
	}
}
public class BrightSlider : Gtk.Box {
    public Gtk.Scale slider;
    //private Gtk.Label value_label;
	public BrightnessWatcher bright = new BrightnessWatcher();
	public signal void changed(double value);
	public bool is_holding = false;
	private ulong slider_handler_id;

    public BrightSlider() {
        // 1. Setup the Outer Box (GTK 3 style)
        // ➡️ In GTK 3, we use the constructor instead of the Object() block for simplicity
        this.orientation = Gtk.Orientation.VERTICAL;
        //this.spacing = 5;

        // 2. Set Margins (GTK 3 uses separate properties)
        //this.margin_top = 10;
        //this.margin_bottom = 10;
        //this.margin_start = 10;
        //this.margin_end = 10;

        // 3. Create the internal Scale (GTK 3)
        slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1);
        slider.hexpand = true;
        slider.draw_value = true;
		slider.set_range(0, 100);

        // 4. Create a Label
        //value_label = new Gtk.Label("Value: 50");

        // 5. Connect logic
        slider.set_value(bright.get_brightness());
		slider_handler_id = slider.value_changed.connect(() => {
            bright.set_brightness(slider.get_value());
        });
		slider.button_press_event.connect(() => { is_holding = true; return false; });
        slider.button_release_event.connect(() => { is_holding = false; return false; });

		bright.brightness_changed.connect((bvalue) => {
            if (!is_holding) {
                GLib.SignalHandler.block(slider, slider_handler_id);
                slider.set_value(bvalue);
                GLib.SignalHandler.unblock(slider, slider_handler_id);
            }
        });

        // 6. Add widgets (GTK 3 uses .add() or .pack_start())
        //this.pack_start(value_label, false, false, 0);
        this.pack_start(slider, true, true, 0);

        // 🎨 Apply Styling (GTK 3 style)
        var context = this.get_style_context();
        context.add_class("slider-box-component");
		context.add_class("slider_long");
    }
}
public class AudioSlider : Gtk.Box {
    public Gtk.Scale slider;
    //private Gtk.Label value_label;
	public VolumeWatcher volume = new VolumeWatcher();
	public signal void changed(double value);
	public bool is_holding = false;
	private ulong slider_handler_id;

    public AudioSlider() {
        // 1. Setup the Outer Box (GTK 3 style)
        // ➡️ In GTK 3, we use the constructor instead of the Object() block for simplicity
        this.orientation = Gtk.Orientation.VERTICAL;
        this.spacing = 5;

        // 2. Set Margins (GTK 3 uses separate properties)
        //this.margin_top = 10;
        //this.margin_bottom = 10;
        //this.margin_start = 10;
        //this.margin_end = 10;

        // 3. Create the internal Scale (GTK 3)
        slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1);
        slider.hexpand = true;
        slider.draw_value = true;
		slider.set_range(0, 100);

        // 4. Create a Label
        //value_label = new Gtk.Label("Value: 50");

        // 5. Connect logic
        //slider.set_value(50);
		slider_handler_id = slider.value_changed.connect(() => {
            volume.set_volume(slider.get_value());
        });
		slider.button_press_event.connect(() => { is_holding = true; return false; });
        slider.button_release_event.connect(() => { is_holding = false; return false; });

		volume.volume_changed.connect((volume_percent, muted) => {
            if (!is_holding) {
                GLib.SignalHandler.block(slider, slider_handler_id);
                slider.set_value(volume_percent);
                GLib.SignalHandler.unblock(slider, slider_handler_id);
            }
        });

        // 6. Add widgets (GTK 3 uses .add() or .pack_start())
        //this.pack_start(value_label, false, false, 0);
        this.pack_start(slider, true, true, 0);

        // 🎨 Apply Styling (GTK 3 style)
        var context = this.get_style_context();
        context.add_class("slider-box-component");
		context.add_class("slider_long");
    }
}

class Battery : Gtk.Box {
    Astal.Icon icon = new Astal.Icon();
    Astal.Label label = new Astal.Label();

    public Battery() {
		var context = this.get_style_context();
        context.add_class("Battery");
		context = icon.get_style_context();
		context.add_class("text");
		context = label.get_style_context();
		context.add_class("text");
        add(icon);
        add(label);
        var bat = AstalBattery.get_default();
        bat.bind_property("is-present", this, "visible", BindingFlags.SYNC_CREATE);
        bat.bind_property("battery-icon-name", icon, "icon", BindingFlags.SYNC_CREATE);
        bat.bind_property("percentage", label, "label", BindingFlags.SYNC_CREATE, (_, src, ref trgt) => {
            var p = Math.floor(src.get_double() * 100);
            trgt.set_string(@"$p%");
            return true;
        });
    }
}

class Time : Astal.Label {
    string format;
    uint interval;

    bool sync() {
        label = new DateTime.now_local().format(format);
        return Source.CONTINUE;
    }

    public Time(string format = "%H:%M:%S  %A %b %e") {
        this.format = format;
        interval = Timeout.add(1000, sync, Priority.DEFAULT);
        destroy.connect(() => Source.remove(interval));
        widget_set_class_names(this, {"Time"});
    }
}


class Left : Gtk.Box {
    public Left(Gdk.Monitor mon) {
        GLib.Object(vexpand: true, hexpand: false);
        add(new Panel(new Media(mon)));
        add(new FocusedClient());

    }
}
class Panel: Gtk.Box {
    public Panel(Gtk.Widget widget){
        GLib.Object(vexpand: true, hexpand: false);
		widget_set_class_names(this, {"panel"});
		add(widget);
    }
}
class Center : Gtk.Box {
    public Center() {
        GLib.Object(vexpand: true, hexpand: false);
        add(new Panel(new Workspaces()));
    }
}
class rightPart: Gtk.Box{
	public int brightness_value = 0;
	public double audio_value { get; set; default = 0; }
    public rightPart(Gdk.Monitor mon){
		var tray_menu_btn = new LabelBtn("󱩖 ");
		var tray_menu = new TrayMenu(mon);
		var brightness_slider = new BrightSlider();
		var audio_slider = new AudioSlider();
		//var speaker = AstalWp.get_default().audio.default_speaker;
		//speaker.bind_property("volume", this, "audio_value", BindingFlags.SYNC_CREATE);
		tray_menu.add_to_tray(new Panel(audio_slider));
		tray_menu.add_to_tray(new Panel(brightness_slider));
        add(new SysTray());
        add(new Wifi());
		tray_menu_btn.clicked.connect(()=> {
			tray_menu.toggle_at_widget(tray_menu_btn);
		});
		add(tray_menu_btn);
		// Initialize from actual values
		this.audio_value = audio_slider.volume.current_volume > 0
			? audio_slider.volume.current_volume
			: 0.0;
		this.brightness_value = (int)brightness_slider.bright.get_brightness();
		tray_menu_btn.my_label.set_label(@"$((int)this.brightness_value) 󱩖 $( "%.1f".printf(this.audio_value) )  ");
		brightness_slider.bright.brightness_changed.connect((percent) => {
			this.brightness_value = (int)percent;
			tray_menu_btn.my_label.set_label(@"$((int)this.brightness_value) 󱩖 $((int)this.audio_value)  ");
			//print("brightness: %f \n", percent);
		});
		audio_slider.volume.volume_changed.connect((percent, muted) => {
			this.audio_value = percent;
			tray_menu_btn.my_label.set_label(@"$((int)this.brightness_value) 󱩖 $( "%.1f".printf(this.audio_value) )  ");
		});
    }
}

class Utils: Gtk.Box{
  private GLib.Subprocess? wlsunset_proc = null;

  public Utils(App app){
    var colorswitch = new Gtk.Button(){
	  visible = true,
	  label = ""
    };
	widget_set_class_names(colorswitch,{"button_inactive","space_right"});
    colorswitch.clicked.connect(()=>{
		widget_set_class_names(colorswitch, {"button_active","space_right"});
		// Run synchronously (script is short-lived)
		Command cmd = new Command({ app.home + "/.config/ags/scripts/color_generation/switchcolor.sh" });
		cmd.spawn_sync();
		app.init_css();
		widget_set_class_names(colorswitch, {"button_inactive","space_right"});
    });
    var screenshot = new Gtk.Button(){
	  visible = true,
	  label = ""
    };
	widget_set_class_names(screenshot,{"button_inactive","space_right"});
    screenshot.clicked.connect(()=>{
		// ✅ Set active style BEFORE spawn (not after)
		widget_set_class_names(screenshot,{"button_active", "space_right"});
		Command cmd = new Command({  app.home + "/.config/ags/scripts/grimblast.sh", "--freeze", "copy", "area" });
		cmd.spawn_sync();
		widget_set_class_names(screenshot,{ "button_inactive", "space_right"});
    });
	// Keep killall -9 wlsunset at startup as requested
	Command k = new Command({"killall", "-9", "wlsunset"});
	k.spawn_sync();
	var reading = new Gtk.ToggleButton(){
		visible = true,
		label = ""
    };
    widget_set_class_names(reading,{"button_inactive"});
	GLib.stdout.printf("please ensure that no wlsunset is running right now \n");
    reading.toggled.connect(()=>{
		if (reading.get_active() && wlsunset_proc == null) {
			widget_set_class_names(reading,{"button_active"});
			GLib.stdout.printf("toggle on \n");
			try {
				wlsunset_proc = new GLib.Subprocess.newv(
					{"/usr/bin/wlsunset", "-T", "5000"},
					GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE
				);
			} catch (GLib.Error e) {
				warning("Failed to start wlsunset: %s", e.message);
				wlsunset_proc = null;
			}
		} else if (!reading.get_active() && wlsunset_proc != null) {
			GLib.stdout.printf("toggle off \n");
			widget_set_class_names(reading,{"button_inactive"});
			wlsunset_proc.force_exit();
			wlsunset_proc = null;
		}
    });
    add(colorswitch);
    add(screenshot);
	add(reading);
  }
}
class Right : Gtk.Box {
    public Right(App app, Gdk.Monitor mon) {
        GLib.Object(vexpand: true, hexpand: false, halign: Gtk.Align.END);
		add(new Panel(new rightPart(mon)));
        add(new Panel(new Battery()));
		add(new Panel(new Utils(app)));
        add(new Panel(new Time()));
    }
}
class Bar : Gtk.Window {
    public Bar(Gdk.Monitor monitor, App app) {
		int width = (int)(monitor.get_geometry().width * (98.7 / 100.0));
		GtkLayerShell.init_for_window(this);
		GtkLayerShell.set_monitor(this, monitor);
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
		GtkLayerShell.auto_exclusive_zone_enable(this);
		print(@"screen width: $width"+"px \n");
        this.get_style_context().add_class("bar");
		var centerbox = new Astal.CenterBox();
		centerbox.start_widget = new Left(monitor);
		centerbox.center_widget = new Center();
		centerbox.end_widget = new Right(app, monitor);
		widget_set_css(centerbox,@"min-width: $width" + "px;");
		widget_set_class_names(centerbox,{ "centerbox" });
		add(centerbox);
		show_all();
    }
}
