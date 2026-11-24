extends Node
## اختبار الحفظ الحقيقي على القرص عبر تشغيلين:
##   المرحلة 1: godot --headless --path godot res://tests/core_persist.tscn -- --core-persist-test --phase=1
##   المرحلة 2: نفس الأمر مع --phase=2 (يتحقق من الاستعادة ومن الغسيل أثناء الإغلاق)


func _ready() -> void:
	await get_tree().process_frame
	var phase := "1"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			phase = a.substr(8)
	if phase == "1":
		GameState.profile.jail_years = 7
		GameState.save_profile()
		GameState.start_state("sahel", 99)
		await get_tree().process_frame
		var s: SettlementData = null
		for d in GameState.state.districts:
			for x in d.settlements:
				if x.has_owner() and x.level == 1 and s == null:
					s = x
		EconomyManager.add_dirty(500000)
		LandManager.researched["1"] = true
		LandManager.buy_title(1)
		GameState.add_item("document", 3)
		LandManager.rent_plot(s.id, s.vacant_plots()[0].id)
		LandManager.place_equipment("laundering_desk")
		EconomyManager.deposit_to_desk(100000)
		EconomyManager.desk_last_unix -= 3600          # كأن ساعة مرت منذ الإيداع قبل الإغلاق
		MotelManager.stash_cash = 1234
		GameState.save_state()
		print("PERSIST phase1 saved home=%s desk=%d" % [LandManager.home_plot, int(EconomyManager.desk_pool)])
	else:
		await get_tree().process_frame
		await get_tree().process_frame
		var ok: bool = GameState.state.id == "sahel" and LandManager.has_home() and LandManager.has_equipment("laundering_desk") \
			and MotelManager.stash_cash == 1234 and int(GameState.profile.jail_years) == 7 and EconomyManager.bank_balance >= 50000
		print("PERSIST phase2 state=%s home=%s desk=%d bank=%d stash=%d years=%d -> %s" % [GameState.state.id, LandManager.home_plot, int(EconomyManager.desk_pool), EconomyManager.bank_balance, MotelManager.stash_cash, int(GameState.profile.jail_years), "pass" if ok else "fail"])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.state_path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.profile_path))
	get_tree().quit()
