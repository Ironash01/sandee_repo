extends Node

func _dump_question(quiz: QuizAltar, m: DungeonMissionData, index: int, label: String) -> void:
	quiz.mission = m
	quiz.set("_questions", m.questions.duplicate())
	quiz.set("_index", index)
	quiz.call("_show_question")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var qtext: Label = quiz.get("_q_text")
	var controls: VBoxContainer = quiz.get("_controls")
	var content: ScrollContainer = quiz.get("_content_scroll")
	print("--- %s | qtext w=%.1f h=%.1f | controls w=%.1f" % [
		label, qtext.size.x, qtext.size.y, controls.size.x])
	for c in controls.get_children():
		if c is CodeEdit:
			print("  CodeEdit w=%.1f h=%.1f text=%s" % [(c as Control).size.x, (c as Control).size.y, JSON.stringify((c as CodeEdit).text.left(80))])
		elif c is Button:
			print("  Button w=%.1f h=%.1f text=%s" % [(c as Control).size.x, (c as Control).size.y, JSON.stringify((c as Button).text.left(80))])
		elif c is PanelContainer:
			print("  OutputPanel w=%.1f h=%.1f" % [(c as Control).size.x, (c as Control).size.y])
		elif c is Label:
			print("  Label w=%.1f h=%.1f text=%s" % [(c as Control).size.x, (c as Control).size.y, JSON.stringify((c as Label).text.left(80))])


func _ready() -> void:
	get_window().size = Vector2i(2000, 900)
	await get_tree().process_frame
	Global.refresh_ui_scale(true)
	Global.load_knowledge_data()

	var failures: Array[String] = []
	var idxs: Array = Global.dungeon_missions.keys()
	idxs.sort()
	for idx in idxs:
		var m: DungeonMissionData = Global.get_dungeon_mission_for_index(int(idx))
		if m == null:
			failures.append("mission %d missing" % int(idx))
			continue
		if m.is_boss():
			continue
		if m.questions.is_empty():
			failures.append("mission %d (%s) has no questions" % [int(idx), m.mission_name])
		for i in range(m.questions.size()):
			var q: DungeonQuestion = m.questions[i]
			var tag := "mission %d Q%d" % [int(idx), i + 1]
			if q == null:
				failures.append(tag + " is null")
				continue
			if q.question.strip_edges().is_empty():
				failures.append(tag + " empty question")
			if q.is_compiler():
				if q.language != "lua" and q.language != "python":
					failures.append(tag + " bad compiler language " + q.language)
				if q.answer_output.is_empty() and not (int(idx) == 37 and i == 0):
					failures.append(tag + " empty answer_output")
			else:
				var opts: Array[String] = q.options()
				var nonempty := 0
				for o in opts:
					if not o.strip_edges().is_empty():
						nonempty += 1
				if nonempty < 2:
					failures.append(tag + " has fewer than 2 options")
				if q.correct_option_index() >= opts.size() or opts[q.correct_option_index()].strip_edges().is_empty():
					failures.append(tag + " correct_index points at empty option")
	print("=== DATA VALIDATION FAILURES: ", failures.size(), " ===")
	for f in failures:
		print("  !! ", f)

	# Layout probe for an MCQ (Lua 26 Q1), a Lua compiler (26 Q2),
	# and a Python compiler (Python 2 Q2).
	var quiz := QuizAltar.new()
	add_child(quiz)
	var panel: Control = quiz.call("_build_panel")
	quiz.set("_panel", panel)
	panel.visible = true

	var lua26: DungeonMissionData = Global.get_dungeon_mission_for_index(26)
	var py2: DungeonMissionData = Global.get_dungeon_mission_for_index(2)
	await _dump_question(quiz, lua26, 0, "Lua 26 Q1 MCQ")
	await _dump_question(quiz, lua26, 1, "Lua 26 Q2 COMPILER")
	await _dump_question(quiz, py2, 1, "Python 2 Q2 COMPILER")

	var knowledge := KnowledgeAltar.new()
	knowledge.setup(lua26)
	add_child(knowledge)
	var kpanel: Control = knowledge.call("_build_panel")
	kpanel.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var kscroll: ScrollContainer = knowledge.get("_content_scroll")
	var kvbox: VBoxContainer = kscroll.get_child(0)
	print("--- KNOWLEDGE 26 | scroll w=%.1f h=%.1f | vbox w=%.1f" % [kscroll.size.x, kscroll.size.y, kvbox.size.x])
	for child in kvbox.get_children():
		if child is Label:
			print("  Label w=%.1f h=%.1f text=%s" % [(child as Control).size.x, (child as Control).size.y, JSON.stringify((child as Label).text.left(60))])

	get_tree().quit()
