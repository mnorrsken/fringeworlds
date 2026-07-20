extends SceneTree
## Headless test runner.
##
## Run with:  godot --headless --script res://tests/run_tests.gd
## (or `make test`). Discovers every `tests/test_*.gd`, instantiates it, and
## calls each `test_*` method, passing a Tester. Exits non-zero if anything
## fails, so it works in CI and Make.

const TESTS_DIR := "res://tests/"

class Tester:
	var checks := 0
	var failures := 0
	var current := ""

	func ok(cond: bool, msg: String) -> void:
		checks += 1
		if not cond:
			failures += 1
			print("  FAIL [%s] %s" % [current, msg])

	func eq(a: Variant, b: Variant, msg: String) -> void:
		ok(a == b, "%s (got %s, expected %s)" % [msg, a, b])


func _init() -> void:
	var t := Tester.new()
	var methods := 0
	for file in DirAccess.get_files_at(TESTS_DIR):
		if not file.begins_with("test_") or not file.ends_with(".gd"):
			continue
		var script: Script = load(TESTS_DIR + file)
		var inst: Object = script.new()
		for m in inst.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			t.current = "%s::%s" % [file, name]
			inst.call(name, t)
			methods += 1

	print("\n== %d assertions across %d tests, %d failures ==" % [t.checks, methods, t.failures])
	quit(1 if t.failures > 0 else 0)
