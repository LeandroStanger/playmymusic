/*-
 * Copyright (c) 2017-2018 Artem Anufrij <artem.anufrij@live.de>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * The Noise authors hereby grant permission for non-GPL compatible
 * GStreamer plugins to be used and distributed together with GStreamer
 * and Noise. This permission is above and beyond the permissions granted
 * by the GPL license by which Noise is covered. If you modify this code
 * you may extend this exception to your version of the code, but you are not
 * obligated to do so. If you do not wish to do so, delete this exception
 * statement from your version.
 *
 * Authored by: Artem Anufrij <artem.anufrij@live.de>
 */

namespace PlayMyMusic.Widgets.Views {
    public class ArtistsView : Gtk.Grid {
        Services.LibraryManager library_manager;
        Settings settings;
        MainWindow mainwindow;

        private string _filter = "";
        public string filter {
            get {
                return _filter;
            } set {
                if (_filter != value) {
                    _filter = value;
                    do_filter ();
                }
            }
        }

        Gtk.FlowBox artists;
        Gtk.Stack stack;

        Widgets.Views.ArtistView artist_view;

        uint timer_sort = 0;
        uint items_found = 0;

        construct {
            settings = Settings.get_default ();
            library_manager = Services.LibraryManager.instance;
            library_manager.added_new_artist.connect ((artist) => {
                Idle.add (() => {
                    add_artist (artist);
                    return false;
                });
            });
        }

        public signal void artist_selected ();

        public ArtistsView (MainWindow mainwindow) {
            this.mainwindow = mainwindow;
            this.mainwindow.ctrl_press.connect (() => {
                foreach (var child in artists.get_selected_children ()) {
                    var artist = child as Widgets.Artist;
                    if (!artist.multi_selection) {
                        artist.toggle_multi_selection (false);
                    }
                }
            });
            build_ui ();
            this.draw.connect (first_draw);
        }

        private bool first_draw () {
            this.draw.disconnect (first_draw);
            activate_by_id (settings.last_artist_id);
            load_background ();
            return false;
        }

        private void build_ui () {
            artists = new Gtk.FlowBox ();
            artists.margin = 24;
            artists.row_spacing = 12;
            artists.valign = Gtk.Align.START;
            artists.max_children_per_line = 1;
            artists.selection_mode = Gtk.SelectionMode.MULTIPLE;
            artists.set_filter_func (artists_filter_func);
            artists.child_activated.connect (show_artist_viewer);

            var artists_scroll = new Gtk.ScrolledWindow (null, null);
            artists_scroll.width_request = 200;
            artists_scroll.add (artists);

            artist_view = new PlayMyMusic.Widgets.Views.ArtistView ();
            artist_view.expand = true;

            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            content.expand = true;
            content.pack_start (artists_scroll, false, false, 0);
            content.pack_end (artist_view, true, true, 0);

            var alert_view = new Granite.Widgets.AlertView (_("No results"), _("Try another search"), "edit-find-symbolic");

            stack = new Gtk.Stack ();
            stack.add_named (content, "content");
            stack.add_named (alert_view, "alert");

            this.add (stack);
            this.show_all ();
        }

        public void add_artist (Objects.Artist artist) {
            var a = new Widgets.Artist (artist);
            lock (artists) {
                artists.add (a);
            }
            a.merge.connect (() => {
                GLib.List<Objects.Artist> selected = new GLib.List<Objects.Artist> ();
                foreach (var child in artists.get_selected_children ()){
                    selected.append ((child as Widgets.Artist).artist);
                }
                artist.merge (selected);
            });
            do_sort ();
        }

        private void do_sort () {
            lock (timer_sort) {
                if (timer_sort != 0) {
                    Source.remove (timer_sort);
                    timer_sort = 0;
                }

                timer_sort = Timeout.add (500, () => {
                    artists.set_sort_func (artists_sort_func);
                    artists.set_sort_func (null);
                    Source.remove (timer_sort);
                    timer_sort = 0;
                    return false;
                });
            }
        }

        private void do_filter () {
            items_found = 0;
            artists.invalidate_filter ();
            if (items_found == 0) {
                stack.visible_child_name = "alert";
            } else {
                stack.visible_child_name = "content";
            }
        }

        public void activate_by_track (Objects.Track track) {
            activate_by_id (track.album.artist.ID);
        }

        public Objects.Artist? activate_by_id (int id) {
            foreach (var child in artists.get_children ()) {
                if ((child as Widgets.Artist).artist.ID == id) {
                    child.activate ();
                    return (child as Widgets.Artist).artist;
                }
            }
            return null;
        }

        public void reset () {
            filter = "";
            foreach (var child in artists.get_children ()) {
                child.destroy ();
            }
            artist_view.reset ();
        }

        public void play_selected_artist () {
            if (artist_view.current_artist != null) {
                artist_view.play_artist ();
            }
        }

        public void load_background () {
            artist_view.load_background ();
        }

        private void show_artist_viewer (Gtk.FlowBoxChild item) {
            if (mainwindow.ctrl_pressed) {
                if ((item as Widgets.Artist).multi_selection) {
                    artists.unselect_child (item);
                    (item as Widgets.Artist).reset ();
                    return;
                } else {
                    (item as Widgets.Artist).toggle_multi_selection (false);
                }
            }
            if (!(item as Widgets.Artist).multi_selection) {
                foreach (var child in artists.get_selected_children ()) {
                    (child as Widgets.Artist).reset ();
                }
                artists.unselect_all ();
                artists.select_child (item);
            }
            var artist = (item as Widgets.Artist).artist;
            settings.last_artist_id = artist.ID;
            artist_view.show_artist_viewer (artist);
            artist_selected ();
        }

        private bool artists_filter_func (Gtk.FlowBoxChild child) {
            if (filter.strip ().length == 0) {
                items_found ++;
                return true;
            }

            string[] filter_elements = filter.strip ().down ().split (" ");
            var artist = (child as Widgets.Artist).artist;

            foreach (string filter_element in filter_elements) {
                if (!artist.name.down ().contains (filter_element)) {
                    bool track_title = false;
                    foreach (var track in artist.tracks) {
                        if (track.title.down ().contains (filter_element) || track.genre.down ().contains (filter_element) || track.album.title.down ().contains (filter_element)) {
                            track_title = true;
                        }
                    }
                    if (track_title) {
                        continue;
                    }
                    return false;
                }
            }
            items_found ++;
            return true;
        }

        private int artists_sort_func (Gtk.FlowBoxChild child1, Gtk.FlowBoxChild child2) {
            var item1 = (Widgets.Artist)child1;
            var item2 = (Widgets.Artist)child2;
            if (item1 != null && item2 != null) {
                return item1.name.collate (item2.name);
            }
            return 0;
        }

        public void unselect_all () {
            foreach (var child in artists.get_selected_children ()) {
                (child as Widgets.Artist).reset ();
            }
            artists.unselect_all ();
        }
    }
}
