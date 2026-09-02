@tool
extends EditorPlugin

## Editor plugin for the Crux addon.
##
## plugin.cfg used to point straight at crux.gd, which is a plain Node. Godot
## requires the script named in plugin.cfg to extend EditorPlugin, so enabling
## the addon failed outright and the documented three-step install could not be
## completed in any order.
##
## crux.gd is a runtime singleton, not an editor tool, so the only job of this
## plugin is to register it as an autoload. That also removes the manual
## "add an autoload named Crux" step the README used to ask for - which was
## itself broken, because a `class_name Crux` in crux.gd collided with an
## autoload of the same name.
##
## _enable_plugin/_disable_plugin are the correct hooks for this (they fire once
## when the user toggles the plugin); _enter_tree would try to re-add the
## autoload on every editor start.

const AUTOLOAD_NAME := "Crux"
const AUTOLOAD_PATH := "res://addons/crux/crux.gd"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
