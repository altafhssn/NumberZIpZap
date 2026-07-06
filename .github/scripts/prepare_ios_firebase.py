from pathlib import Path


project = Path("project.godot")
text = project.read_text(encoding="utf-8")

autoload = 'FirebaseIOS="*res://addons/GodotFirebaseiOS/FirebaseIOS.gd"'
if autoload not in text:
    marker = 'FirebaseBackend="*res://scripts/FirebaseBackend.gd"'
    if marker not in text:
        raise SystemExit("FirebaseBackend autoload marker not found")
    text = text.replace(marker, autoload + "\n" + marker, 1)

plugin = '"res://addons/GodotFirebaseiOS/plugin.cfg"'
if plugin not in text:
    marker = '"res://addons/GodotFirebaseAndroid/plugin.cfg"'
    if marker not in text:
        raise SystemExit("Android Firebase plugin marker not found")
    text = text.replace(marker, marker + ", " + plugin, 1)

project.write_text(text, encoding="utf-8")

# The upstream exporter edits project.pbxproj as raw text. Disable that call;
# the Swift/XcodeProj configurator applies the same linker settings safely.
exporter = Path("addons/GodotFirebaseiOS/export_plugin.gd")
source = exporter.read_text(encoding="utf-8")
unsafe_call = "\n\t\t_modify_pbxproj(_export_path)\n"
if source.count(unsafe_call) != 1:
    raise SystemExit("Unexpected iOS exporter layout; refusing an unsafe patch")
source = source.replace(
    unsafe_call,
    "\n\t\tprint(\"GodotFirebaseiOS: linker settings delegated to CI Swift configurator\")\n",
)
exporter.write_text(source, encoding="utf-8")
