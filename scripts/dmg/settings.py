# dmgbuild settings for Snippets.dmg. release.sh passes -D app=<path> and
# -D background=<path> (settings files get no __file__ to resolve it from).
# Sizes and positions must match Layout in render-background.swift, which
# draws the wells and arrow around these icon spots.
import os.path
import plistlib

application = defines["app"]  # noqa: F821 (dmgbuild injects `defines`)
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}

# The volume shows the app's own icon rather than a generic disk.
badge_icon = None
with open(os.path.join(application, "Contents/Info.plist"), "rb") as f:
    icon_file = plistlib.load(f)["CFBundleIconFile"]
icon = os.path.join(application, "Contents/Resources",
                    icon_file if icon_file.endswith(".icns") else icon_file + ".icns")

# background@2x.png next to it is picked up for Retina screens.
background = defines["background"]  # noqa: F821

# 400 pt of background plus Finder's 32 pt title bar. A path or status bar
# (global Finder settings a DMG can't turn off) covers the bottom instead,
# so nothing essential is drawn in the last ~60 pt.
window_rect = ((200, 120), (640, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 144
text_size = 13
label_pos = "bottom"
arrange_by = None
icon_locations = {
    appname: (172, 206),
    "Applications": (468, 206),
}
