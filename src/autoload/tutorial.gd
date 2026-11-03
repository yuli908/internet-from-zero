extends Node

## 引导服务：顺序步骤 + 事件触发。UI 只负责显示当前步骤。

var runner: TutorialRunner

func _ready() -> void:
	runner = TutorialRunner.from_doc(DataDB.tutorial_doc)
	EventBus.game_event.connect(_on_game_event)

func _on_game_event(event_name: String) -> void:
	if GameState.player == null or runner == null:
		return
	var step := runner.on_event(GameState.player, event_name)
	if not step.is_empty():
		EventBus.tutorial_updated.emit(step)
		EventBus.state_changed.emit()

func current_step() -> Dictionary:
	if GameState.player == null or runner == null:
		return {}
	return runner.current(GameState.player)

func acknowledge() -> Dictionary:
	if GameState.player == null or runner == null:
		return {}
	var step := runner.acknowledge(GameState.player)
	EventBus.tutorial_updated.emit(step)
	EventBus.state_changed.emit()
	return step

func progress() -> Dictionary:
	if GameState.player == null or runner == null:
		return {"done": 0, "total": 0}
	return runner.progress(GameState.player)
