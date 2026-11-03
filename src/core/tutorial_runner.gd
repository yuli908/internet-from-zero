class_name TutorialRunner
extends RefCounted

## 引导步骤顺序推进，由事件触发或玩家手动确认。

var steps: Array = []

static func from_doc(doc: Dictionary) -> TutorialRunner:
	var t := TutorialRunner.new()
	for raw in doc.get("steps", []):
		if raw is Dictionary:
			t.steps.append(raw)
	return t

func current(state: PlayerState) -> Dictionary:
	for raw in steps:
		if raw is Dictionary:
			var s: Dictionary = raw
			if not state.is_tutorial_done(str(s.get("id", ""))):
				return s
	return {}

func acknowledge(state: PlayerState) -> Dictionary:
	var s := current(state)
	if s.is_empty():
		return {}
	state.mark_tutorial_done(str(s.get("id", "")))
	return s

func on_event(state: PlayerState, event_name: String) -> Dictionary:
	var s := current(state)
	if s.is_empty():
		return {}
	if str(s.get("trigger", "")) == event_name:
		state.mark_tutorial_done(str(s.get("id", "")))
		return s
	return {}

func done(state: PlayerState) -> bool:
	return current(state).is_empty()

func progress(state: PlayerState) -> Dictionary:
	var done := 0
	for raw in steps:
		if raw is Dictionary and state.is_tutorial_done(str(raw.get("id", ""))):
			done += 1
	return {"done": done, "total": steps.size()}
