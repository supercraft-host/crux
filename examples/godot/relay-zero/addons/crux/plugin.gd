@tool
extends EditorPlugin

# The runtime SDK is registered separately as the Crux autoload. This editor
# plugin intentionally stays minimal so the addon can be enabled without
# trying to instantiate the runtime Node as an EditorPlugin.
func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
