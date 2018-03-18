/*-
 * Copyright (c) 2017-2017 Artem Anufrij <artem.anufrij@live.de>
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
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

namespace PlayMyMusic.Objects {
    public class MobilePhoneMusicFolder : Granite.Widgets.SourceList.ExpandableItem, Granite.Widgets.SourceListSortable, Granite.Widgets.SourceListDragDest {
        PlayMyMusic.Services.LibraryManager library_manager;

        public signal void subfolder_created (File file);
        public signal void subfolder_deleted ();

        public File file { get; private set; }

        construct {
            library_manager = PlayMyMusic.Services.LibraryManager.instance;
        }

        public MobilePhoneMusicFolder (string uri) {
            file = File.new_for_uri (uri);
            this.name = file.get_basename ();
            get_subfolders ();
        }

        private void get_subfolders () {
            try {
                var children = file.enumerate_children ("standard::*", GLib.FileQueryInfoFlags.NONE);
                FileInfo file_info = null;
                while ((file_info = children.next_file ()) != null) {
                    if (file_info.get_file_type () == FileType.DIRECTORY) {
                        create_album_folder (file.get_uri () + "/" + file_info.get_name ());
                    }
                }
            } catch (Error err) {
                warning (err.message);
            }
        }

        public MobilePhoneMusicFolder? get_sub_folder (string sub) {
            foreach (var child in this.children) {
                if ((child is MobilePhoneMusicFolder) && child.name == sub) {
                    return child as MobilePhoneMusicFolder;
                }
            }

            var sub_folder = File.new_for_uri (file.get_uri () + "/" + sub);
            try {
                sub_folder.make_directory ();
                return create_album_folder (sub_folder.get_uri ());
            } catch (Error err) {
                warning (err.message);
            }
            return null;
        }

        private MobilePhoneMusicFolder create_album_folder (string uri) {
            var sub = new MobilePhoneMusicFolder (uri);
            sub.subfolder_deleted.connect (() => subfolder_deleted ());
            this.add (sub);
            return sub;
        }

        public void delete () {
            this.name = _("deleting…");
            new Thread<void*> (null, () => {
                PlayMyMusic.Utils.delete_uri_recursive (file.get_uri ());
                this.parent.remove (this);
                Idle.add (() => {
                    subfolder_deleted ();
                    return false;
                });
                return null;
            });
        }

        private bool data_drop_possible (Gdk.DragContext context, Gtk.SelectionData data) {
            var received = data.get_text ();

            if (!received.has_prefix ("Album:") && !received.has_prefix ("Artist:")) {
                return false;
            }

            var targets = PlayMyMusicApp.instance.mainwindow.mobile_phone_view.folders.root.children;
            foreach (var target in targets) {
                if (target == this) {
                    return true;
                }
            }
            return false;
        }

        private Gdk.DragAction data_received (Gdk.DragContext context, Gtk.SelectionData data) {
            var received = data.get_text ();
            if (received.has_prefix ("Album:")) {
                var str_id = received.substring (6);

                int id = int.parse (str_id);
                if (id > 0) {
                    var album = library_manager.get_album_by_id (id);
                    if (album != null) {
                        var current_mobile_phone = PlayMyMusicApp.instance.mainwindow.mobile_phone_view.current_mobile_phone;
                        if (current_mobile_phone != null) {
                            current_mobile_phone.add_album (album, this);
                        }
                    }
                }
            } else if (received.has_prefix ("Artist:")) {
                var str_id = received.substring (7);
                int id = int.parse (str_id);
                if (id > 0) {
                    var artist = library_manager.get_artist_by_id (id);
                    if (artist != null) {
                        var current_mobile_phone = PlayMyMusicApp.instance.mainwindow.mobile_phone_view.current_mobile_phone;
                        if (current_mobile_phone != null) {
                            current_mobile_phone.add_artist (artist, this);
                        }
                    }
                }
            }

            return Gdk.DragAction.COPY;
        }

        public int compare (Granite.Widgets.SourceList.Item a, Granite.Widgets.SourceList.Item b) {
            if (a is MobilePhoneMusicFolder && b is MobilePhoneMusicFolder) {
                return (a as MobilePhoneMusicFolder).name.collate ((b as MobilePhoneMusicFolder).name);
            }
            return 0;
        }

        public bool allow_dnd_sorting () {
            return false;
        }
    }
}
