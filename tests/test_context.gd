class_name TestContext
extends RefCounted

var checks := 0
var failures := 0
var suite := ""
var failure_messages: Array = []

func begin(name: String) -> void:
	suite = name

func check(label: String, cond: bool, detail: String = "") -> bool:
	checks += 1
	if not cond:
		failures += 1
		var msg := "[%s] %s" % [suite, label]
		if not detail.is_empty():
			msg += " :: " + detail
		failure_messages.append(msg)
		print("  FAIL ", msg)
		return false
	return true

func eq(label: String, actual: Variant, expected: Variant) -> bool:
	return check(label, actual == expected, "期望 %s，实际 %s" % [str(expected), str(actual)])

func close(label: String, actual: float, expected: float, tol: float = 0.0001) -> bool:
	return check(label, absf(actual - expected) <= tol, "期望 %f，实际 %f" % [expected, actual])

func ne(label: String, actual: Variant, unexpected: Variant) -> bool:
	return check(label, actual != unexpected, "实际值不应等于 %s" % str(unexpected))

func report() -> bool:
	print("RESULT: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		for msg in failure_messages:
			print("  - ", msg)
	return failures == 0
