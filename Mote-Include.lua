-------------------------------------------------------------------------------------------------------------------
-- Common variables and functions to be included in job scripts.
-- Include this file in the get_sets() function with the command:
-- include('Mote-Include.lua')
-- or
-- include(player.name..'/Mote-Include.lua')
-- depending on where you keep your files -- in the data/ directory or the data/<player.name> directory.
--
-- You then MUST run init_include()
--
-- It should be the first command in the get_sets() function, but must at least be executed before
-- any included vars are referenced.
--
-- Included variables and functions are considered to be at the same scope level as
-- the job script itself, and can be used as such.
--
-- This script has access to any vars defined at the job lua's scope, such as player and world.
-------------------------------------------------------------------------------------------------------------------

-- Last Modified: 12/27/2013 4:55:31 AM

-- Define the include module as a table (clean, forwards compatible with lua 5.2).
local _MoteInclude = {}


-------------------------------------------------------------------------------------------------------------------
-- Initialization function that defines variables to be used.
-- These are accessible at the including job lua script's scope.
-------------------------------------------------------------------------------------------------------------------

function _MoteInclude.init_include()
	-- Var for tracking state values
	state = {}
	
	-- General melee offense/defense modes, allowing for hybrid set builds, as well as idle/resting/weaponskill.
	state.OffenseMode     = 'Normal'
	state.DefenseMode     = 'Normal'
	state.WeaponskillMode = 'Normal'
	state.CastingMode     = 'Normal'
	state.IdleMode        = 'Normal'
	state.RestingMode     = 'Normal'
	
	-- All-out defense state, either physical or magical
	state.Defense = {}
	state.Defense.Active       = false
	state.Defense.Type         = 'Physical'
	state.Defense.PhysicalMode = 'PDT'
	state.Defense.MagicalMode  = 'MDT'

	state.Kiting               = false
	state.MaxWeaponskillDistance = 0
	
	state.SelectNPCTargets     = false
	state.PCTargetMode         = 'default'
	
	-- Vars for tracking valid modes
	options = {}
	options.OffenseModes = {'Normal', 'Acc','Crit'}
	options.DefenseModes = {'Normal', 'PDT', 'Evasion','Counter'}
	options.WeaponskillModes = {'Normal', 'PDT', 'Evasion','Counter'}
	options.CastingModes = {'Normal'}
	options.IdleModes = {'Normal'}
	options.RestingModes = {'Normal'}
	options.PhysicalDefenseModes = {'PDT', 'Evasion'}
	options.MagicalDefenseModes = {'MDT', 'Resist'}

	-- General cast delay value to be sure gear that's equipped on precast
	-- actually takes effect.  Adjust to suit.
	-- Only use if verify_equip isn't appropriate.
	options.CastDelay = 0.35
	
	options.TargetModes = {'default', 'stpc', 'stpt', 'stal'}
	

	-- Spell mappings defined in a function at the bottom of this file
	classes = {}
	classes.spellMappings = get_spell_mappings()
	-- Custom class, like the generic spell mappings.  Gets reset after every use.
	classes.CustomClass = nil
	
	
	-- Stuff for handling self commands
	selfCommands = {['toggle']=handle_toggle, ['activate']=handle_activate, ['cycle']=handle_cycle, ['set']=handle_set,
		['reset']=handle_reset, ['update']=handle_update, ['test']=handle_test}
		
	-- Display text mapping.
	on_off_names = {[true] = 'on', [false] = 'off'}


	-- Set to allow us to determine if we're in a city zone.
	-- Eventually may add other types of zone groups.
	areas = {}
	areas.Cities = S{"ru'lude gardens", 'upper jeuno','lower jeuno','port jeuno',
		'port windurst','windurst waters','windurst woods','windurst walls','heavens tower',
		"port san s'oria","northern san s'oria","southern san s'oria",
		'port bastok','bastok markets','bastok mines','metalworks',
		'aht urhgan whitegate','tavanazian safehold','nashmau',
		'selbina','mhaura','norg','eastern adoulin','western adoulin'}

	-- Flag to indicate whether midcast gear was used on precast.
	precastUsedMidcastGear = false
	-- Flag whether the job lua changed the spell to be used.
	spellWasChanged = false
	-- Flag whether we changed the target of the spell.
	targetWasChanged = false

	-- Vars for use in melee set construction.
	TPWeapon = 'Normal'
	CustomMeleeGroup = 'Normal'


	-- Other general vars.  Set whatever's convenient for your job luas.
	
	staffs = {}
	staffs.HMP = 'Chatoyant Staff'
	staffs.PDT = 'Earth Staff'
	staffs.Cure = 'Arka IV'
	staffs.GeneralMagicAcc = 'Soothsayer Staff'
	staffs.BlmMagicAcc = 'Atinian Staff'
	
end


-------------------------------------------------------------------------------------------------------------------
-- Generalized functions for handling precast/midcast/aftercast actions.
-- This depends on proper set naming.
-- Each job can override any amount of these general functions using job_xxx() hooks.
-------------------------------------------------------------------------------------------------------------------

-- Called before sending the command to execute the desired action.
-- Define the set to be equipped at this point in time based on the type of action.
function _MoteInclude.precast(spell,action)
	local spellMap = classes.spellMappings[spell.english]
	
	-- First allow for spell changes before we consider changing the target.
	-- This is a job-specific matter.
	if job_handle_spell_changes and not spellWasChanged and not targetWasChanged then
		local spellCancelled, spellChanged = job_handle_spell_changes(spell,action,spellMap)
		
		if spellCancelled then
			if spellChanged then
				spellWasChanged = true
			end
			return
		end
	end
	
	spellWasChanged = false

	
	-- Handle optional target conversion (t to stpc/etc).  If we changed target, exit so this can be called
	-- after proper target selection was done.
	if not targetWasChanged then
		if convert_target(spell,action,spellMap) then
			targetWasChanged = true
			return
		end
	end
	
	targetWasChanged = false

	local preHandled = false

	-- Allow jobs to have first shot at setting up the precast gear.
	if job_precast then
		preHandled, useMidcastGear = job_precast(spell, action, spellMap)
	end

	if not preHandled then

		--cast_delay(options.CastDelay)
		verify_equip()

		if action.type == 'Magic' then
			local spellTiming = 'precast.FC'
			if spell.casttime <= 1 or useMidcastGear then
				useMidcastGear = true
				precastUsedMidcastGear = {true, spell.english}
				spellTiming = 'midcast'
			end
			
			-- Call this to break 'precast.FC' into a proper set.
			local baseSet = get_expanded_set(sets, spellTiming)
			local equipSet = {}

			-- Use midcast sets if cast time is too short (TODO: override this with custom fast cast calculations)
			-- Set determination ordering:
			-- Specific spell name
			-- Custom class
			-- Class mapping
			-- Skill
			-- Spell type
			if baseSet[spell.english] then
				equipSet = baseSet[spell.english]
			elseif classes.CustomClass and baseSet[classes.CustomClass] then
				equipSet = baseSet[classes.CustomClass]
			elseif spellMap and baseSet[spellMap] then
				equipSet = baseSet[spellMap]
			elseif baseSet[spell.skill] then
				equipSet = baseSet[spell.skill]
			elseif baseSet[spell.type] then
				equipSet = baseSet[spell.type]
			else
				equipSet = baseSet
			end
			
			-- Check for specialized casting modes for any given set selection.
			if equipSet[state.CastingMode] then
				equipSet = equipSet[state.CastingMode]
			end

			equip(equipSet)

			-- Magian staves with fast cast on them
			if baseSet[tostring(spell.element)] then
				equip(baseSet[tostring(spell.element)])
			end
			
			--if tonumber(spell.casttime) >= 4 then verify_equip() end
		elseif spell.type == 'JobAbility' then
			if sets.precast.JA[spell.english] then
				equip(sets.precast.JA[spell.english])
			end
		elseif spell.type == 'Weaponskill' then
			local modeToUse = state.WeaponskillMode
			if state.WeaponskillMode == 'Normal' then
				if state.OffenseMode ~= 'Normal' and S(options.WeaponskillModes)[state.OffenseMode] then
					modeToUse = state.OffenseMode
				end
			end
			
			if sets.precast.WS[spell.english] then
				if sets.precast.WS[spell.english][modeToUse] then
					equip(sets.precast.WS[spell.english][modeToUse])
				else
					equip(sets.precast.WS[spell.english])
				end
			elseif classes.CustomClass and sets.precast.WS[classes.CustomClass] then
				if sets.precast.WS[classes.CustomClass][modeToUse] then
					equip(sets.precast.WS[classes.CustomClass][modeToUse])
				else
					equip(sets.precast.WS[classes.CustomClass])
				end
			else
				if sets.precast.WS[modeToUse] then
					equip(sets.precast.WS[modeToUse])
				else
					equip(sets.precast.WS)
				end
			end

		elseif sets.precast[spell.type] then
			if sets.precast[spell.type][spell.english] then
				equip(sets.precast[spell.type][spell.english])
			else
				equip(sets.precast[spell.type])
			end
		end
	end
	
	-- Allow followup code to add to what was done here
	local holdCustomClass = false
	if job_post_precast then
		holdCustomClass = job_post_precast(spell, action, spellMap, useMidcastGear)
	end

	-- Reset CustomClass after every pass.
	if not holdCustomClass then
		classes.CustomClass = nil
	end
end


-- Called when a player starts casting a spell.
function _MoteInclude.midcast(spell,action)
	if precastUsedMidcastGear then
		if _global.debug_mode then add_to_chat(123,'Midcast gear was used in precast, so skipping midcast phase.') end
		precastUsedMidcastGear = false
		return
	end

	local preHandled = false
	
	local spellMap = classes.spellMappings[spell.english]
	
	-- Allow jobs to override this code
	if job_midcast then
		preHandled = job_midcast(spell, action, spellMap)
	end

	if not preHandled then
		if action.type == 'Magic' then
			local spellMap = classes.spellMappings[spell.english]

			local equipSet = {}
			
			-- Set determination ordering:
			-- Specific spell name
			-- Custom class
			-- Class mapping
			-- Skill
			-- Spell type
			if sets.midcast[spell.english] then
				equipSet = sets.midcast[spell.english]
			elseif classes.CustomClass and sets.midcast[classes.CustomClass] then
				equipSet = sets.midcast[classes.CustomClass]
			elseif spellMap and sets.midcast[spellMap] then
				equipSet = sets.midcast[spellMap]
			elseif sets.midcast[spell.skill] then
				equipSet = sets.midcast[spell.skill]
			elseif sets.midcast[spell.type] then
				equipSet = sets.midcast[spell.type]
			else
				equipSet = sets.midcast
			end

			-- Check for specialized casting modes for any given set selection.
			if equipSet[state.CastingMode] then
				equipSet = equipSet[state.CastingMode]
			end

			equip(equipSet)
		end
	end
	
	-- Allow followup code to add to what was done here
	local holdCustomClass = false
	if job_post_midcast then
		holdCustomClass = job_post_midcast(spell, action, spellMap)
	end

	if not holdCustomClass then
		classes.CustomClass = nil
	end
end


-- Called when an action has been completed (eg: spell finished casting, or failed to cast).
function _MoteInclude.aftercast(spell,action)
	local preHandled = false

	-- Allow jobs to override this code
	if job_aftercast then
		preHandled = job_aftercast(spell, action)
	end

	if not preHandled then
		if spell.interrupted then
			-- Wait a half-second to update so that aftercast equip will actually be worn.
			windower.send_command('wait 0.6;gs c update')
		else
			handle_equipping_gear(player.status)
		end
	end

	-- Allow followup code to add to what was done here
	if job_post_aftercast then
		job_post_aftercast(spell, action)
	end
end


-- Called when the player's status changes.
function _MoteInclude.status_change(newStatus, oldStatus)
	local preHandled = false

	-- Allow jobs to override this code
	if job_status_change then
		preHandled = job_status_change(newStatus, oldStatus)
	end

	if not preHandled then
		handle_equipping_gear(newStatus)
	end
end

-------------------------------------------------------------------------------------------------------------------
-- Generalized functions for selecting and equipping gear sets.
-------------------------------------------------------------------------------------------------------------------

-- Function to wrap logic for equipping gear on aftercast, status change, or user update.
-- @param status : The current or new player status that determines what sort of gear to equip. (string)
function _MoteInclude.handle_equipping_gear(status)
	-- Assume idle status if the status value is blank (eg: after first logging in)
	if _global.debug_mode then add_to_chat(123,'Debug: Equip gear for status ['..status..']') end
	if status == 'Idle' or status == '' then
		equip(get_current_idle_set())
	elseif status == 'Engaged' then
		equip(get_current_melee_set())
	elseif status == 'Resting' then
		equip(get_current_resting_set())
	end
end

-- Returns the appropriate idle set based on current state.
function _MoteInclude.get_current_idle_set()
	local idleScope = ''
	local idleSet = {}

	if buffactive.weakness then
		idleScope = 'Weak'
	elseif areas.Cities[world.area:lower()] then
		idleScope = 'Town'
	else
		idleScope = 'Field'
	end
	
	if _global.debug_mode then add_to_chat(123,'Debug: Idle scope for ['..world.area..'] is ['..idleScope..']') end

	if sets.idle[idleScope] then
		if sets.idle[idleScope][state.IdleMode] then
			idleSet = sets.idle[idleScope][state.IdleMode]
		else
			idleSet = sets.idle[idleScope]
		end
	else
		idleSet = sets.idle
	end
	
	idleSet = apply_defense(idleSet)
	idleSet = apply_kiting(idleSet)
	
	if customize_idle_set then
		idleSet = customize_idle_set(idleSet)
	end

	--if _global.debug_mode then print_set(idleSet, 'Idle Set') end
	
	return idleSet
end

-- Returns the appropriate melee set based on current state.
function _MoteInclude.get_current_melee_set()
	local meleeSet = {}
	
	if sets.engaged[CustomMeleeGroup] then
		if sets.engaged[CustomMeleeGroup][TPWeapon] then
			meleeSet = sets.engaged[CustomMeleeGroup][TPWeapon]
			
			if meleeSet[state.OffenseMode] then
				meleeSet = meleeSet[state.OffenseMode]
			end
			
			if meleeSet[state.DefenseMode] then
				meleeSet = meleeSet[state.DefenseMode]
			end
		else
			meleeSet = sets.engaged[CustomMeleeGroup]
	
			if meleeSet[state.OffenseMode] then
				meleeSet = meleeSet[state.OffenseMode]
			end
			
			if meleeSet[state.DefenseMode] then
				meleeSet = meleeSet[state.DefenseMode]
			end
		end
	else
		if sets.engaged[TPWeapon] then
			meleeSet = sets.engaged[TPWeapon]
			
			if meleeSet[state.OffenseMode] then
				meleeSet = meleeSet[state.OffenseMode]
			end
			
			if meleeSet[state.DefenseMode] then
				meleeSet = meleeSet[state.DefenseMode]
			end
		else
			meleeSet = sets.engaged
	
			if meleeSet[state.OffenseMode] then
				meleeSet = meleeSet[state.OffenseMode]
			end
			
			if meleeSet[state.DefenseMode] then
				meleeSet = meleeSet[state.DefenseMode]
			end
		end
	end
	
	meleeSet = apply_defense(meleeSet)
	meleeSet = apply_kiting(meleeSet)

	if customize_melee_set then
		meleeSet = customize_melee_set(meleeSet)
	end

	--if _global.debug_mode then print_set(meleeSet, 'Melee set') end
	
	return meleeSet
end

-- Returns the appropriate resting set based on current state.
function _MoteInclude.get_current_resting_set()
	local restingSet = {}
	
	if sets.resting[state.RestingMode] then
		restingSet = sets.resting[state.RestingMode]
	else
		restingSet = sets.resting
	end

	--if _global.debug_mode then print_set(restingSet, 'Resting Set') end
	
	return restingSet
end

-- Function to apply any active defense set on top of the supplied set
-- @param baseSet : The set that any currently active defense set will be applied on top of. (gear set table)
function _MoteInclude.apply_defense(baseSet)
	if state.Defense.Active then
		local defenseSet = {}
		local defMode = ''
		
		if state.Defense.Type == 'Physical' then
			defMode = state.Defense.PhysicalMode
			
			if sets.defense[state.Defense.PhysicalMode] then
				defenseSet = sets.defense[state.Defense.PhysicalMode]
			else
				defenseSet = sets.defense
			end
		else
			defMode = state.Defense.MagicalMode

			if sets.defense[state.Defense.MagicalMode] then
				defenseSet = sets.defense[state.Defense.MagicalMode]
			else
				defenseSet = sets.defense
			end
		end
		
		baseSet = set_combine(baseSet, defenseSet)
	end
	
	return baseSet
end

-- Function to add kiting gear on top of the base set if kiting state is true.
-- @param baseSet : The set that the kiting gear will be applied on top of. (gear set table)
function _MoteInclude.apply_kiting(baseSet)
	if state.Kiting then
		if sets.Kiting then
			baseSet = set_combine(baseSet, sets.Kiting)
		end
	end
	
	return baseSet
end


-------------------------------------------------------------------------------------------------------------------
-- General functions for manipulating state values.
-- Only specifically handles state and such that we've defined within this include.
-------------------------------------------------------------------------------------------------------------------

-- Routing function for general known self_commands.
-- Handles splitting the provided command line up into discrete words, for the other functions to use.
function _MoteInclude.self_command(cmd)
	splitCmd = splitwords(cmd)
	if #splitCmd == 0 then
		return
	end
	
	-- Allow jobs to override this
	local preHandled = false

	if job_self_command then
		preHandled = job_self_command(splitCmd)
	end

	if not preHandled then
		-- Quick custom commands
		if splitCmd[1]:lower() == 'showtpset' then
			equip(get_current_melee_set())
			return
		end
		
		-- Of the original command message passed in, remove the first word from
		-- the list (it will be used to determine which function to call), and
		-- send the remaining words are parameters for the function.
		local handleCmd = table.remove(splitCmd, 1)
		
		if selfCommands[handleCmd] then
			selfCommands[handleCmd](splitCmd)
		end
	end
end


-- Individual handling of self commands --


-- Handle toggling specific vars that we know of.
-- Valid toggles: Defense, Kiting
-- Returns true if a known toggle was handled.  Returns false if not.
-- User command format: gs c toggle [field]
function _MoteInclude.handle_toggle(cmdParams)
	if #cmdParams > 0 then
		-- identifier for the field we're toggling
		local toggleField = cmdParams[1]:lower()
		
		if toggleField == 'defense' then
			state.Defense.Active = not state.Defense.Active
			add_to_chat(122,state.Defense.Type..' defense is now '..on_off_names[state.Defense.Active]..'.')
		elseif toggleField == 'kite' or toggleField == 'kiting' then
			state.Kiting = not state.Kiting
			add_to_chat(122,'Kiting is now '..on_off_names[state.Kiting]..'.')
		elseif toggleField == 'target' then
			state.SelectNPCTargets = not state.SelectNPCTargets
			add_to_chat(122,'NPC targetting is now '..on_off_names[state.SelectNPCTargets]..'.')
		else
			if _global.debug_mode then add_to_chat(123,'Unknown toggle field: '..toggleField) end
			return false
		end
	else
		if _global.debug_mode then add_to_chat(123,'--handle_toggle parameter failure: field not specified') end
		return false
	end
	
	handle_update({'auto'})
	return true
end


-- Function to handle turning on particular states, while possibly also setting a mode value.
-- User command format: gs c activate [field]
function _MoteInclude.handle_activate(cmdParams)
	if #cmdParams > 0 then
		activateState = cmdParams[1]:lower()
		
		if activateState == 'physicaldefense' then
			state.Defense.Active = true
			state.Defense.Type = 'Physical'
			add_to_chat(122,'Physical defense is now on.')
		elseif activateState == 'magicaldefense' then
			state.Defense.Active = true
			state.Defense.Type = 'Magical'
			add_to_chat(122,'Magical defense is now on.')
		elseif activateState == 'kite' or activateState == 'kiting' then
			state.Kiting = true
			add_to_chat(122,'Kiting is now on.')
		elseif toggleField == 'target' then
			state.SelectNPCTargets = true
			add_to_chat(122,'NPC targetting is now on.')
		else
			if _global.debug_mode then add_to_chat(123,'--handle_activate unknown state to activate: '..activateState) end
		end
	else
		if _global.debug_mode then add_to_chat(123,'--handle_activate parameter failure: field not specified') end
		return false
	end
	
	handle_update({'auto'})
	return true
end


-- Handle cycling through the options for specific vars that we know of.
-- Valid fields: OffenseMode, DefenseMode, WeaponskillMode, IdleMode, RestingMode, CastingMode, PhysicalDefenseMode, MagicalDefenseMode
-- All fields must end in 'Mode'
-- Returns true if a known toggle was handled.  Returns false if not.
-- User command format: gs c cycle [field]
function _MoteInclude.handle_cycle(cmdParams)
	if #cmdParams > 0 then
		-- identifier for the field we're toggling
		local paramField = cmdParams[1]:lower()

		if string_ends_with(paramField, 'mode') then
			-- Remove 'mode' from the end of the string
			local modeField = paramField:sub(1,#paramField-4)
			-- Convert WS to Weaponskill
			if modeField == "ws" then
				modeField = "weaponskill"
			end
			-- Capitalize the field (for use on output display)
			modeField = modeField:gsub("%a", string.upper, 1)

			-- Get the options.XXXModes table, and the current state mode for the mode field.
			local modeTable, currentValue = get_mode_table(modeField)

			-- Get the index of the current mode.  'Normal' or undefined is treated as index 0.
			local invertedTable = invert_table(modeTable)
			local index = 0
			if invertedTable[currentValue] then
				index = invertedTable[currentValue]
			end
			
			-- Increment to the next index in the available modes.
			index = index + 1
			if index > #modeTable then
				index = 1
			end
			
			-- Determine the new mode value based on the index.
			local newModeValue = ''
			if index and modeTable[index] then
				newModeValue = modeTable[index]
			else
				newModeValue = 'Normal'
			end
			
			-- And save that to the appropriate state field.
			set_mode(modeField, newModeValue)
			
			-- Display what got changed to the user.
			add_to_chat(122,modeField..' mode is now '..newModeValue..'.')
		else
			if _global.debug_mode then add_to_chat(123,'Invalid cycle field (does not end in "mode"): '..paramField) end
			return false
		end
	else
		if _global.debug_mode then add_to_chat(123,'--handle_cycle parameter failure: field not specified') end
		return false
	end
	handle_update({'auto'})
	return true
end

-- Function to set various states to specific values directly.
-- User command format: gs c set [field] [value]
function _MoteInclude.handle_set(cmdParams)
	if #cmdParams > 1 then
		-- identifier for the field we're setting
		local field = cmdParams[1]
		local lowerField = field:lower()
		local setField = cmdParams[2]
		
		
		-- Check if we're dealing with a boolean
		if T{'on', 'off', 'true', 'false'}:contains(setField) then
			local setValue = T{'on', 'true'}:contains(setField)
			
			if lowerField == 'defense' then
				state.Defense.Active = setValue
				add_to_chat(122,state.Defense.Type..' defense is now '..on_off_names[state.Defense.Active]..'.')
			elseif lowerField == 'kite' or lowerField == 'kiting' then
				state.Kiting = setValue
				add_to_chat(122,'Kiting is now '..on_off_names[state.Kiting]..'.')
			elseif lowerField == 'target' then
				state.SelectNPCTargets = setValue
				add_to_chat(122,'NPC targetting is now '..on_off_names[state.SelectNPCTargets]..'.')
			else
				if _global.debug_mode then add_to_chat(123,'Unknown field: '..field) end
				return false
			end
		-- Or if we're dealing with a mode setting
		elseif string_ends_with(lowerField, 'mode') then
			-- Remove 'mode' from the end of the string
			modeField = lowerField:sub(1,#lowerField-4)
			-- Convert WS to Weaponskill
			if modeField == "ws" then
				modeField = "weaponskill"
			end
			-- Capitalize the field (for use on output display)
			modeField = modeField:gsub("%a", string.upper, 1)
			
			-- Get the options.XXXModes table, and the current state mode for the mode field.
			local modeTable, currentValue = get_mode_table(modeField)
			
			-- Check if the new setting exists in the mode table
			if modeTable[setField] then
				-- And save that to the appropriate state field.
				set_mode(modeField, setField)
			
				-- Display what got changed to the user.
				add_to_chat(122,modeField..' mode is now '..newModeValue..'.')
			else
				if _global.debug_mode then add_to_chat(123,'Unknown mode value: '..setField..' for '..modeField..' mode.') end
				return false
			end
		-- Or issueing a command where the user doesn't/can't provide the value
		elseif lowerField == 'distance' then
			if setField then
				local possibleDistance = tonumber(setField)
				if possibleDistance ~= nil then
					state.MaxWeaponskillDistance = possibleDistance
				else
					add_to_chat(123,'Invalid distance value: '..setField)
				end
				
				-- set max weaponskill distance to the current distance the player is from the mob.

				add_to_chat(123,'Using max weaponskill distance is not implemented right now.')
			else
				-- Get current player distance and use that
				add_to_chat(123,'TODO: get player distance.')
			end
		else
			if _global.debug_mode then add_to_chat(123,'Unknown set handling: '..field..' : '..setField) end
			return false
		end
	else
		if _global.debug_mode then add_to_chat(123,'--handle_set parameter failure: insufficient fields') end
		return false
	end
	
	handle_update({'auto'})
	return true
end


-- Function to turn off togglable features, or reset values to their defaults.
-- User command format: gs c reset [field]
function _MoteInclude.handle_reset(cmdParams)
	if #cmdParams > 0 then
		resetState = cmdParams[1]:lower()
		
		if resetState == 'defense' then
			state.Defense.Active = false
			add_to_chat(122,state.Defense.Type..' defense is now off.')
		elseif resetState == 'kite' or resetState == 'kiting' then
			state.Kiting = false
			add_to_chat(122,'Kiting is now off.')
		elseif resetState == 'melee' then
			state.OffenseMode = options.OffenseModes[1]
			state.DefenseMode = options.DefenseModes[1]
			add_to_chat(122,'Melee has been reset to defaults.')
		elseif resetState == 'casting' then
			state.CastingMode = options.CastingModes[1]
			add_to_chat(122,'Casting has been reset to default.')
		elseif resetState == 'distance' then
			state.MaxWeaponskillDistance = 0
			add_to_chat(122,'Max weaponskill distance limitations have been removed.')
		elseif resetState == 'target' then
			state.SelectNPCTargets = false
			state.PCTargetMode = 'default'
			add_to_chat(122,'Adjusting target selection has been turned off.')
		elseif resetState == 'all' then
			state.Defense.Active = false
			state.Defense.PhysicalMode = options.PhysicalDefenseModes[1]
			state.Defense.MagicalMode = options.MagicalDefenseModes[1]
			state.Kiting = false
			state.OffenseMode = options.OffenseModes[1]
			state.DefenseMode = options.DefenseModes[1]
			state.CastingMode = options.CastingModes[1]
			state.IdleMode = options.IdleModes[1]
			state.RestingMode = options.RestingModes[1]
			state.MaxWeaponskillDistance = 0
			state.SelectNPCTargets = false
			state.PCTargetMode = 'default'
			add_to_chat(122,'Everything has been reset to defaults.')
		else
			if _global.debug_mode then add_to_chat(123,'--handle_reset unknown state to reset: '..resetState) end
		end
	else
		if _global.debug_mode then add_to_chat(123,'--handle_activate parameter failure: field not specified') end
		return false
	end
	
	handle_update({'auto'})
	return true
end


-- User command format: gs c update [option]
-- Where [option] can be 'user' to display current state.
-- Otherwise, generally refreshes current gear used.
function _MoteInclude.handle_update(cmdParams)
	local preHandled = false
	if job_update then
		preHandled = job_update(cmdParams)
	end
	
	if not preHandled then
		handle_equipping_gear(player.status)
	end
	
	if cmdParams[1] == 'user' then
		display_current_state()
	end
end


-- A test function for testing lua code.
function _MoteInclude.handle_test(cmdParams)
end



------  Utility functions to support self commands. ------

-- Function to get the options.XXXModes table and the corresponding state value to make given state field.
function _MoteInclude.get_mode_table(field)
	local modeTable = {}
	local currentValue = ''

	if field == 'Offense' then
		modeTable = options.OffenseModes
		currentValue = state.OffenseMode
	elseif field == 'Defense' then
		modeTable = options.DefenseModes
		currentValue = state.DefenseMode
	elseif field == 'Casting' then
		modeTable = options.CastingModes
		currentValue = state.CastingMode
	elseif field == 'Weaponskill' then
		modeTable = options.WeaponskillModes
		currentValue = state.WeaponskillMode
	elseif field == 'Idle' then
		modeTable = options.IdleModes
		currentValue = state.IdleMode
	elseif field == 'Resting' then
		modeTable = options.RestingModes
		currentValue = state.RestingMode
	elseif field == 'Physicaldefense' then
		modeTable = options.PhysicalDefenseModes
		currentValue = state.Defense.PhysicalMode
	elseif field == 'Magicaldefense' then
		modeTable = options.MagicalDefenseModes
		currentValue = state.Defense.MagicalMode
	elseif field == 'Target' then
		modeTable = options.TargetModes
		currentValue = state.PCTargetMode
	elseif job_get_mode_table then
		-- Allow job scripts to expand the mode table lists
		modeTable, currentValue, err = job_get_mode_table(field)
		if err then
			if _global.debug_mode then add_to_chat(123,'Attempt to query unknown state field: '..field) end
			return nil
		end
	else
		if _global.debug_mode then add_to_chat(123,'Attempt to query unknown state field: '..field) end
		return nil
	end
	
	return modeTable, currentValue
end

-- Function to set the appropriate state value for the specified field.
function _MoteInclude.set_mode(field, val)
	if field == 'Offense' then
		state.OffenseMode = val
	elseif field == 'Defense' then
		state.DefenseMode = val
	elseif field == 'Casting' then
		state.CastingMode = val
	elseif field == 'Weaponskill' then
		state.WeaponskillMode = val
	elseif field == 'Idle' then
		state.IdleMode = val
	elseif field == 'Resting' then
		state.RestingMode = val
	elseif field == 'Physicaldefense' then
		state.Defense.PhysicalMode = val
	elseif field == 'Magicaldefense' then
		state.Defense.MagicalMode = val
	elseif field == 'Target' then
		state.PCTargetMode = val
	elseif job_set_mode then
		-- Allow job scripts to expand the mode table lists
		if not job_set_mode(field, val) then
			if _global.debug_mode then add_to_chat(123,'Attempt to set unknown state field: '..field) end
		end
	else
		if _global.debug_mode then add_to_chat(123,'Attempt to set unknown state field: '..field) end
	end
end


-- Function to display the current relevant user state when doing an update.
-- Uses display_current_job_state instead if that is defined in the job lua.
function _MoteInclude.display_current_state()
	local preHandled = false
	if display_current_job_state then
		preHandled = display_current_job_state()
	end
	
	if not preHandled then
		local defenseString = ''
		if state.Defense.Active then
			local defMode = state.Defense.PhysicalMode
			if state.Defense.Type == 'Magical' then
				defMode = state.Defense.MagicalMode
			end
	
			defenseString = 'Defense: '..state.Defense.Type..' '..defMode..', '
		end

		add_to_chat(122,'Melee: '..state.OffenseMode..'/'..state.DefenseMode..', WS: '..state.WeaponskillMode..', '..defenseString..
			'Kiting: '..on_off_names[state.Kiting]..', Select target: '..state.PCTargetMode..' (PC) / '..on_off_names[state.SelectNPCTargets]..' (NPC)')
	end
end

-------------------------------------------------------------------------------------------------------------------
-- Utility functions for vars or other data manipulation.
-------------------------------------------------------------------------------------------------------------------

-- Function to split words based on whitespace.
-- Returns an array of the words found in the provided message.
function _MoteInclude.splitwords(msg)
	local splitarr = T{}

	-- whitespace-separated components (without handling quotes)
	--for word in str:gmatch("%S+") do
	for word in string.gmatch(msg, "%f[%w]%S+%f[%W]") do
		splitarr[#splitarr+1] = word
	end

	return splitarr
end


-- Determine if a string ends with a specified ending string.
function _MoteInclude.string_ends_with(String, End)
	return End=='' or string.sub(String,-string.len(End))==End
end


-- Invert a table such that the keys are values and the values are keys.
-- Use this to look up the index value of a given entry.
function _MoteInclude.invert_table(t)
	if t == nil then add_to_chat(123,'Attempting to invert table, received nil.') end
	
	local i={}
	for k,v in pairs(t) do 
		i[v] = k
	end
	return i
end

-- Gets sub-tables based on baseSet from the string str that may be in dot form
-- (eg: baseSet=sets, str='precast.FC', this returns sets.precast.FC).
function _MoteInclude.get_expanded_set(baseSet, str)
	local cur = baseSet
	for i in str:gmatch("[^.]+") do
		cur = cur[i]
	end
	
	return cur
end


function _MoteInclude.convert_target(spell, action, spellMap)
	-- If the original command already used a target selection, or is explicitly <me>, return.
	if spell.target.raw:find('<st') or spell.target.raw == ('<lastst>') or spell.target.raw == ('<me>') then
		return
	end
	
	-- Allow the job to do custom handling
	if job_convert_target then
		local preHandled, converted =  job_convert_target(spell, action, spellMap)
		if preHandled then
			return converted
		end
	end
			

	local canUseOnPC = spell.validtarget.Self or spell.validtarget.Player or spell.validtarget.Party or spell.validtarget.Ally or spell.validtarget.NPC

	local newTarget = ''
	
	-- Check if we want to adjust targetting for player characters
	if canUseOnPC then
		if state.PCTargetMode == 'stal' then
			-- Limit choice based on what the valid targets of the spell are.
			if spell.validtarget.Ally then
				newTarget = '<stal>'
			elseif spell.validtarget.Party then
				newTarget = '<stpt>'
			elseif spell.validtarget.Self then
				newTarget = '<me>'
			end
		elseif state.PCTargetMode == 'stpt' then
			-- Limit choice based on what the valid targets of the spell are.
			if spell.validtarget.Ally or spell.validtarget.Party then
				newTarget = '<stpt>'
			elseif spell.validtarget.Self then
				newTarget = '<me>'
			end
		elseif state.PCTargetMode == 'stpc' then
			-- Limit choice based on what the valid targets of the spell are.
			if spell.validtarget.Player or spell.validtarget.Party or spell.validtarget.Ally or spell.validtarget.NPC then
				newTarget = '<stpc>'
			elseif spell.validtarget.Self then
				newTarget = '<me>'
			end
		end
	-- Check if we want to adjust targtting for enemies
	elseif state.SelectNPCTargets and spell.validtarget.Enemy then
		newTarget = '<stnpc>'
	end
	
	if newTarget ~= '' and newTarget ~= spell.target.raw then
		change_target(newTarget)
		return true
	end
end


-------------------------------------------------------------------------------------------------------------------
-- Handle generic binds on load/unload of GearSwap.
-------------------------------------------------------------------------------------------------------------------


-- Function to bind GearSwap binds when loading a GS script.
function _MoteInclude.gearswap_binds_on_load()
	windower.send_command('bind f9 gs c cycle OffenseMode')
	windower.send_command('bind ^f9 gs c cycle DefenseMode')
	windower.send_command('bind !f9 gs c cycle WeaponskillMode')
	windower.send_command('bind f10 gs c activate PhysicalDefense')
	windower.send_command('bind ^f10 gs c cycle PhysicalDefenseMode')
	windower.send_command('bind !f10 gs c toggle kiting')
	windower.send_command('bind f11 gs c activate MagicalDefense')
	windower.send_command('bind ^f11 gs c cycle CastingMode')
	windower.send_command('bind !f11 gs c set CastingMode Dire')
	windower.send_command('bind f12 gs c update user')
	windower.send_command('bind ^f12 gs c cycle IdleMode')
	windower.send_command('bind !f12 gs c reset defense')
end

-- Function to re-bind Spellcast binds when unloading GearSwap.
function _MoteInclude.spellcast_binds_on_unload()
	windower.send_command('bind f9 input /ma CombatMode Cycle(Offense)')
	windower.send_command('bind ^f9 input /ma CombatMode Cycle(Defense)')
	windower.send_command('bind !f9 input /ma CombatMode Cycle(WS)')
	windower.send_command('bind f10 input /ma PhysicalDefense .On')
	windower.send_command('bind ^f10 input /ma PhysicalDefense .Cycle')
	windower.send_command('bind !f10 input /ma CombatMode Toggle(Kite)')
	windower.send_command('bind f11 input /ma MagicalDefense .On')
	windower.send_command('bind ^f11 input /ma CycleCastingMode')
	windower.send_command('bind !f11 input /ma CastingMode Dire')
	windower.send_command('bind f12 input /ma Update .Manual')
	windower.send_command('bind ^f12 input /ma CycleIdleMode')
	windower.send_command('bind !f12 input /ma Reset .Defense')
end

-------------------------------------------------------------------------------------------------------------------
-- Handle generic binds on load/unload of GearSwap.
-------------------------------------------------------------------------------------------------------------------

-- Returns a table of spell mappings to allow grouping classes of spells that are otherwise disparately named.
function _MoteInclude.get_spell_mappings()
	local mappings = {
		['Cure']='Cure',['Cure II']='Cure',['Cure III']='Cure',['Cure IV']='Cure',['Cure V']='Cure',['Cure VI']='Cure',
		['Cura']='Curaga',['Cura II']='Curaga',['Cura III']='Curaga',
		['Curaga']='Curaga',['Curaga II']='Curaga',['Curaga III']='Curaga',['Curaga IV']='Curaga',['Curaga V']='Curaga',
		['Barfire']='Barspell',['Barstone']='Barspell',['Barwater']='Barspell',['Baraero']='Barspell',['Barblizzard']='Barspell',['Barthunder']='Barspell',
		['Barfira']='Barspell',['Barstonra']='Barspell',['Barwatera']='Barspell',['Baraera']='Barspell',['Barblizzara']='Barspell',['Barthundra']='Barspell',
		['Foe Lullaby']='Lullaby',['Foe Lullaby II']='Lullaby',['Horde Lullaby']='Lullaby',['Horde Lullaby II']='Lullaby',
		["Mage's Ballad"]='Ballad',["Mage's Ballad II"]='Ballad',["Mage's Ballad III"]='Ballad',
		['Advancing March']='March',['Victory March']='March',
		['Sword Madrigal']='Madrigal',['Blade Madrigal']='Madrigal',
		['Valor Minuet']='Minuet',['Valor Minuet II']='Minuet',['Valor Minuet III']='Minuet',['Valor Minuet IV']='Minuet',['Valor Minuet V']='Minuet',
		["Knight's Minne"]='Minne',["Knight's Minne II"]='Minne',["Knight's Minne III"]='Minne',["Knight's Minne IV"]='Minne',["Knight's Minne V"]='Minne',
		["Army's Paeon"]='Paeon',["Army's Paeon II"]='Paeon',["Army's Paeon III"]='Paeon',["Army's Paeon IV"]='Paeon',["Army's Paeon V"]='Paeon',["Army's Paeon VI"]='Paeon',
		['Fire Carol']='Carol',['Ice Carol']='Carol',['Wind Carol']='Carol',['Earth Carol']='Carol',['Lightning Carol']='Carol',['Water Carol']='Carol',['Light Carol']='Carol',['Dark Carol']='Carol',
		['Fire Carol II']='Carol',['Ice Carol II']='Carol',['Wind Carol II']='Carol',['Earth Carol II']='Carol',['Lightning Carol II']='Carol',['Water Carol II']='Carol',['Light Carol II']='Carol',['Dark Carol II']='Carol',
		['Regen']='Regen',['Regen II']='Regen',['Regen III']='Regen',['Regen IV']='Regen',['Regen V']='Regen',
		['Protect']='Protect',['Protect II']='Protect',['Protect III']='Protect',['Protect IV']='Protect',['Protect V']='Protect',
		['Shell']='Shell',['Shell II']='Shell',['Shell III']='Shell',['Shell IV']='Shell',['Shell V']='Shell',
		['Protectra']='Protectra',['Protectra II']='Protectra',['Protectra III']='Protectra',['Protectra IV']='Protectra',['Protectra V']='Protectra',
		['Shellra']='Shellra',['Shellra II']='Shellra',['Shellra III']='Shellra',['Shellra IV']='Shellra',['Shellra V']='Shellra',
		-- Status Removal doesn't include Esuna or Sacrifice, since they work differently than the rest
		['Poisona']='StatusRemoval',['Paralyna']='StatusRemoval',['Silena']='StatusRemoval',['Blindna']='StatusRemoval',['Cursna']='StatusRemoval',
		['Stona']='StatusRemoval',['Viruna']='StatusRemoval',['Erase']='StatusRemoval',
		['Utsusemi: Ichi']='Utsusemi',['Utsusemi: Ni']='Utsusemi',
		['Burn']='ElementalEnfeeble',['Frost']='ElementalEnfeeble',['Choke']='ElementalEnfeeble',['Rasp']='ElementalEnfeeble',['Shock']='ElementalEnfeeble',['Drown']='ElementalEnfeeble',
	}

	return mappings
end


-- Done with defining the module.  Return the table.
return _MoteInclude
