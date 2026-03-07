# Workspace Rules

- When the task involves Godot, GDScript, `.gd`, `.tscn`, scenes, nodes, signals, `@export`, `@onready`, `NodePath`, shaders, resources, autoloads, or Godot project structure, always use `$godot-gdscript` for that turn.
- When the task involves running Godot from the command line, choosing between GUI and console executables, startup smoke tests, parser/runtime startup verification, or headless validation, always use `$godot-headless-run` for that turn.
- When the task involves `user://` logs, file logging, `FileAccess`, `DirAccess`, log rotation, debug traces, or permission-safe runtime logging, always use `$godot-safe-logging` for that turn.
- If a headless run fails first in logging, `user://`, `FileAccess`, or directory creation, classify that as an independent blocker and do not attribute the failure to the unrelated change under review.
- For non-trivial Godot changes, read the relevant scenes, neighboring scripts, and project settings before editing.
- When a Godot change modifies node names, script attachments, exported paths, autoloads, input actions, or scene structure, update the corresponding project files together with the `.gd` files.
