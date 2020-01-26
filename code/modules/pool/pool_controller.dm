//Originally stolen from paradise. Credits to tigercat2000.
//Modified a lot by Kokojo and Tortellini Tony for hippiestation.
//Heavily refactored by tgstation
/obj/machinery/pool
	icon = 'icons/obj/machines/pool.dmi'
	anchored = TRUE

/obj/machinery/pool/controller
	name = "\improper Pool Controller"
	desc = "An advanced substance generation and fluid tank management system that can refill the contents of a pool to a completely different substance in minutes."
	icon_state = "poolc_3"
	density = TRUE
	use_power = TRUE
	idle_power_usage = 75
	resistance_flags = INDESTRUCTIBLE
	/// How far it scans for pool objects
	var/scan_range = 6
	/// Is pool mist currently on?
	var/mist_state = FALSE
	/// Linked mist effects
	var/list/obj/effect/mist/linked_mist = list()
	/// Pool turfs
	var/list/turf/open/pool/linked_turfs = list()
	/// All mobs in pool
	var/list/mob/living/mobs_in_pool = list()
	/// Is the pool bloody?
	var/bloody = 0
	/// Last time we process_reagents()'d
	var/last_reagent_process = 0
	/// Maximum amount we will take from a beaker
	var/max_beaker_transfer = 100
	/// Minimum amount of a reagent for it to work on us
	var/min_reagent_amount = 10
	/// ADMINBUS ONLY - WHETHER OR NOT WE HAVE NOREACT ;)
	var/noreact_reagents = FALSE
	/// how fast in deciseconds between reagent processes
	var/reagent_tick_interval = 5
	/// Can we use unsafe temperatures
	var/temperature_unlocked = FALSE
	/// See __DEFINES/pool.dm, temperature defines
	var/temperature = POOL_NORMAL
	/// Whether or not the pool can be drained
	var/drainable = FALSE
	// Whether or not the pool is drained
	var/drained = FALSE
	/// Pool drain
	var/obj/machinery/pool/drain/linked_drain
	/// Pool filter
	var/obj/machinery/pool/filter/linked_filter
	/// Next world.time you can interact with settings
	var/interact_delay = 0
	/// Airlock style shocks
	var/shocked = FALSE
	/// Old reagent color, used to determine if update_color needs to reset colors.
	var/old_rcolor

/obj/machinery/pool/controller/Initialize()
	. = ..()
	START_PROCESSING(SSfastprocess, src)
	create_reagents(1000)
	if(noreact_reagents)
		reagents.reagent_holder_flags |= NO_REACTION
	wires = new /datum/wires/poolcontroller(src)
	scan_things()

/obj/machinery/pool/controller/Destroy()
	STOP_PROCESSING(SSprocessing, src)
	linked_drain = null
	linked_filter = null
	linked_turfs.Cut()
	mobs_in_pool.Cut()
	return ..()

/obj/machinery/pool/controller/proc/scan_things()
	var/list/cached = range(scan_range, src)
	for(var/turf/open/pool/W in cached)
		linked_turfs += W
		W.controller = src
	for(var/obj/machinery/pool/drain/pooldrain in cached)
		linked_drain = pooldrain
		linked_drain.pool_controller = src
		break
	for(var/obj/machinery/pool/filter/F in cached)
		linked_filter = F
		linked_filter.pool_controller = src
		break

/obj/machinery/pool/controller/emag_act(mob/user)
	. = ..()
	if(!(obj_flags & EMAGGED)) //If it is not already emagged, emag it.
		to_chat(user, "<span class='warning'>You disable the [src]'s safety features.</span>")
		do_sparks(5, TRUE, src)
		obj_flags |= EMAGGED
		temperature_unlocked = TRUE
		drainable = TRUE
		log_game("[key_name(user)] emagged [src]")
		message_admins("[key_name_admin(user)] emagged [src]")
	else
		to_chat(user, "<span class='warning'>The interface on [src] is already too damaged to short it again.</span>")
		return

/obj/machinery/pool/controller/attackby(obj/item/W, mob/user)
	if(shocked && !(stat & NOPOWER))
		shock(user,50)
	if(stat & (BROKEN))
		return
	if(istype(W,/obj/item/reagent_containers))
		if(!W.reagents.total_volume) //check if there's reagent
			for(var/datum/reagent/R in W.reagents.reagent_list)
				if(R.type in GLOB.blacklisted_pool_reagents)
					to_chat(user, "[src] cannot accept [R.name].")
					return
				if(R.reagent_state == SOLID)
					to_chat(user, "The pool cannot accept reagents in solid form!.")
					return
			reagents.clear_reagents()
			// This also reacts them. No nitroglycerin deathpools, sorry gamers :(
			W.reagents.trans_to(reagents, max_beaker_transfer)
			user.visible_message("<span class='notice'>[src] makes a slurping noise.</span>", "<span class='notice'>All of the contents of [W] are quickly suctioned out by the machine!</span")
			updateUsrDialog()
			var/list/reagent_names = list()
			var/list/rejected = list()
			for(var/datum/reagent/R in reagents.reagent_list)
				if(R.volume >= min_reagent_amount)
					reagent_names += R.name
				else
					reagents.remove_reagent(R.type, INFINITY)
					rejected += R.name
			if(length(reagent_names))
				reagent_names = english_list(reagent_names)
				log_game("[key_name(user)] has changed the [src] chems to [reagent_names]")
				message_admins("[key_name_admin(user)] has changed the [src] chems to [reagent_names].")
			if(length(rejected))
				rejected = english_list(rejected)
				to_chat(user, "<span class='warning'>[src] rejects the following chemicals as they do not have at least [min_reagent_amount] units of volume: [rejected]</span>")
		else
			to_chat(user, "<span class='notice'>[src] beeps unpleasantly as it rejects the beaker. Why are you trying to feed it an empty beaker?</span>")
			return
	else if(panel_open && is_wire_tool(W))
		wires.interact(user)
	else
		return ..()

/obj/machinery/pool/controller/screwdriver_act(mob/living/user, obj/item/W)
	. = ..()
	if(.)
		return TRUE
	cut_overlays()
	panel_open = !panel_open
	to_chat(user, "You [panel_open ? "open" : "close"] the maintenance panel.")
	W.play_tool_sound(src)
	if(panel_open)
		add_overlay("wires")
	return TRUE

//procs
/obj/machinery/pool/controller/proc/shock(mob/user, prb)
	if(stat & (BROKEN|NOPOWER))		// unpowered, no shock
		return FALSE
	if(!prob(prb))
		return FALSE
	var/datum/effect_system/spark_spread/s = new /datum/effect_system/spark_spread
	s.set_up(5, 1, src)
	s.start()
	if(electrocute_mob(user, get_area(src), src, 0.7))
		return TRUE
	else
		return FALSE

/obj/machinery/pool/controller/proc/process_reagents()
	if(last_reagent_process > world.time + reagent_tick_interval)
		return
	if(length(reagents.reagent_list) > 0)
		for(var/turf/open/pool/W in linked_turfs)
			for(var/mob/living/carbon/human/swimee in W)
				for(var/datum/reagent/R in reagents.reagent_list)
					if(R.reagent_state == SOLID)
						R.reagent_state = LIQUID
					swimee.reagents.add_reagent(R.name, 0.5) //osmosis
				reagents.reaction(swimee, VAPOR, 0.03) //3 percent
			for(var/obj/objects in W)
				if(W.reagents)
					W.reagents.reaction(objects, VAPOR, 1)
	last_reagent_process = world.time

/obj/machinery/pool/controller/process()
	updateUsrDialog()
	if(stat & (NOPOWER|BROKEN))
		return
	if (!drained)
		process_pool()
		if(reagent_delay <= world.time)
			process_reagents()

/obj/machinery/pool/controller/proc/process_pool()
	if(!drained)
		for(var/mob/living/M in mobs_in_pool)
			switch(temperature) //Apply different effects based on what the temperature is set to.
				if(POOL_SCALDING) //Scalding
					M.adjust_bodytemperature(50,0,500)
				if(POOL_WARM) //Warm
					M.adjust_bodytemperature(20,0,360) //Heats up mobs till the termometer shows up
				//Normal temp does nothing, because it's just room temperature water.
				if(POOL_COOL)
					M.adjust_bodytemperature(-20,250) //Cools mobs till the termometer shows up
				if(POOL_FRIGID) //Freezing
					M.adjust_bodytemperature(-60) //cool mob at -35k per cycle, less would not affect the mob enough.
					if(M.bodytemperature <= 50 && !M.stat)
						M.apply_status_effect(/datum/status_effect/freon)
			if(ishuman(M))
				var/mob/living/carbon/human/drownee = M
				if(!drownee || drownee.stat == DEAD)
					return
				if(drownee.lying && !drownee.internal)
					if(drownee.stat != CONSCIOUS)
						drownee.adjustOxyLoss(9)
					else
						drownee.adjustOxyLoss(4)
						if(prob(35))
							to_chat(drownee, "<span class='danger'>You're drowning!</span>")

/obj/machinery/pool/controller/proc/set_bloody(state)
	if(bloody == state)
		return
	bloody = state
	update_color()

/obj/machinery/pool/controller/proc/update_color()
	if(drained)
		return
	var/rcolor
	if(reagents.reagent_list.len)
		rcolor = mix_color_from_reagents(reagents.reagent_list)
	if(rcolor == old_rcolor)
		return // small performance upgrade hopefully?
	old_rcolor = rcolor
	for(var/X in linked_turfs)
		var/turf/open/pool/color1 = X
		if(bloody)
			if(rcolor)
				color1.watereffect.color = BlendRGB(rgb(150, 20, 20), rcolor, 0.5)
				color1.watertop.color = color1.watereffect.color
			else
				color1.watereffect.color = rgb(150, 20, 20)
				color1.watertop.color = color1.watereffect.color
		else if(!bloody && rcolor)
			color1.watereffect.color = rcolor
			color1.watertop.color = color1.watereffect.color
		else
			color1.watereffect.color = null
			color1.watertop.color = null

/obj/machinery/pool/controller/proc/update_temp()
	if(mist_status)
		if(temperature < POOL_SCALDING)
			mist_off()
	else
		if(temperature == POOL_SCALDING)
			mist_on()
	update_icon()

/obj/machinery/pool/controller/update_icon()
	. = ..()
	icon_state = "poolc_[temperature]"

/obj/machinery/pool/controller/proc/CanUpTemp(mob/user)
	if(temperature == POOL_WARM && (temperature_unlocked || issilicon(user) || IsAdminGhost(user)) || temperature < POOL_WARM)
		return TRUE
	return FALSE

/obj/machinery/pool/controller/proc/CanDownTemp(mob/user)
	if(temperature == POOL_COOL && (temperature_unlocked || issilicon(user) || IsAdminGhost(user)) || temperature > POOL_COOL)
		return TRUE
	return FALSE

/obj/machinery/pool/controller/Topic(href, href_list)
	if(..())
		return
	if(interact_delay > world.time)
		return
	if(href_list["IncreaseTemp"])
		if(CanUpTemp(usr))
			temperature++
			update_temp()
			interact_delay = world.time + 15
	if(href_list["DecreaseTemp"])
		if(CanDownTemp(usr))
			temperature--
			update_temp()
			interact_delay = world.time + 15
	if(href_list["Activate Drain"])
		if((drainable || issilicon(usr) || IsAdminGhost(usr)) && !linked_drain.active)
			mistoff()
			interact_delay = world.time + 60
			linked_drain.active = TRUE
			linked_drain.timer = 15
			if(!linked_drain.status)
				new /obj/effect/whirlpool(linked_drain.loc)
				temperature = POOL_NORMAL
			else
				new /obj/effect/waterspout(linked_drain.loc)
				temperature = POOL_NORMAL
			update_temp()
			bloody = FALSE
	updateUsrDialog()

/obj/machinery/pool/controller/proc/temp2text()
	switch(temperature)
		if(POOL_FRIGID)
			return "<span class='bad'>Frigid</span>"
		if(POOL_COOL)
			return "<span class='good'>Cool</span>"
		if(POOL_NORMAL)
			return "<span class='good'>Normal</span>"
		if(POOL_WARM)
			return "<span class='good'>Warm</span>"
		if(POOL_SCALDING)
			return "<span class='bad'>Scalding</span>"
		else
			return "Outside of possible range."

/obj/machinery/pool/controller/ui_interact(mob/user)
	. = ..()
	if(.)
		return
	if(shocked && !(stat & NOPOWER))
		shock(user,50)
	if(panel_open && !isAI(user))
		return wires.interact(user)
	if(stat & (NOPOWER|BROKEN))
		return
	var/datum/browser/popup = new(user, "Pool Controller", name, 300, 450)
	var/dat = ""
	if(interact_delay > world.time)
		dat += "<span class='notice'>[(interact_delay - world.time)] seconds left until [src] can operate again.</span><BR>"
	dat += text({"
		<h3>Temperature</h3>
		<div class='statusDisplay'>
		<B>Current temperature:</B> [temp2text()]<BR>
		[CanUpTemp(user) ? "<a href='?src=\ref[src];IncreaseTemp=1'>Increase Temperature</a><br>" : "<span class='linkOff'>Increase Temperature</span><br>"]
		[CanDownTemp(user) ? "<a href='?src=\ref[src];DecreaseTemp=1'>Decrease Temperature</a><br>" : "<span class='linkOff'>Decrease Temperature</span><br>"]
		</div>
		<h3>Drain</h3>
		<div class='statusDisplay'>
		<B>Drain status:</B> [(issilicon(user) || IsAdminGhost(user) || drainable) ? "<span class='bad'>Enabled</span>" : "<span class='good'>Disabled</span>"]
		<br><b>Pool status:</b> "})
	if(!drained)
		dat += "<span class='good'>Full</span><BR>"
	else
		dat += "<span class='bad'>Drained</span><BR>"
	if((issilicon(user) || IsAdminGhost(user) || drainable) && !linked_drain.active)
		dat += "<a href='?src=\ref[src];Activate Drain=1'>[drained ? "Fill" : "Drain"] Pool</a><br>"
	popup.set_content(dat)
	popup.open()

/obj/machinery/pool/controller/proc/reset(wire)
	switch(wire)
		if(WIRE_SHOCK)
			if(!wires.is_cut(wire))
				shocked = FALSE

/obj/machinery/pool/controller/proc/mist_on() //Spawn /obj/effect/mist (from the shower) on all linked pool tiles
	if(mist_state)
		return
	mist_state = TRUE
	for(var/X in linked_turfs)
		var/turf/open/pool/W = X
		if(W.filled)
			var/M = new /obj/effect/mist(W)
			linked_mist += M

/obj/machinery/pool/controller/proc/mist_off() //Delete all /obj/effect/mist from all linked pool tiles.
	for(var/M in linked_mist)
		qdel(M)
	mist_state = FALSE
