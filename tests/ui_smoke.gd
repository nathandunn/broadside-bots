extends SceneTree
## Drive the UI headless through a few screens to catch runtime errors.
func _init():
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for role in ["Trader", "Pirate"]:
		main._start(role)
		await process_frame
		main._port_screen()
		if role == "Trader":
			main.sail_to("oranjestad")
		else:
			main.note(Sim.cruise(main.state, 20))
		await process_frame
		for i in 30:
			main._sail_until()
			await process_frame
			if not main.state.encounter.is_empty():
				main._act("attack" if role == "Pirate" else "flee")
				await process_frame
			if main.state.ended or not main.state.at_sea():
				break
		main.refresh()
		await process_frame
		print(role, " ok: ", main.state.journal.slice(-3))
	main._new_career()
	await process_frame
	print("UI SMOKE DONE")
	quit()
