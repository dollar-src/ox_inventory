if not lib then return end

local Utils = client.utils
local Weapon = client.weapon
local currentWeapon

RegisterNetEvent('ox_inventory:disarm', function()
	currentWeapon = Weapon.Disarm(currentWeapon)
end)

RegisterNetEvent('ox_inventory:clearWeapons', function()
	Weapon.ClearAll(currentWeapon)
end)

local StashTarget

exports('setStashTarget', function(id, owner)
	StashTarget = id and {id=id, owner=owner}
end)

---@type boolean | number | nil
local invBusy = true

---@type boolean?
local invOpen = false

local plyState = LocalPlayer.state

plyState:set('invBusy', true, false)

local function canOpenInventory()
	return PlayerData.loaded
	and not invBusy
	and not PlayerData.dead
	and invOpen ~= nil
	and (not currentWeapon or currentWeapon.timer == 0)
	and not IsPedCuffed(cache.ped)
	and not IsPauseMenuActive()
	and not IsPedFatallyInjured(cache.ped)
end

local defaultInventory = {
	type = 'newdrop',
	slots = shared.playerslots,
	weight = 0,
	maxWeight = shared.playerweight,
	items = {}
}
local currentInventory = defaultInventory

local function closeTrunk()
	if currentInventory?.type == 'trunk' then
		local coords = GetEntityCoords(cache.ped, true)
		Utils.PlayAnimAdvanced(900, 'anim@heists@fleeca_bank@scope_out@return_case', 'trevor_action', coords.x, coords.y, coords.z, 0.0, 0.0, GetEntityHeading(cache.ped), 2.0, 2.0, 1000, 49, 0.25)
		CreateThread(function()
			local entity = currentInventory.entity
			local door = currentInventory.door
			Wait(900)
			SetVehicleDoorShut(entity, door, false)
		end)
	end
end

---@param inv string
---@param data table | string | number
---@return boolean?
function client.openInventory(inv, data)
	if invOpen then
		if not inv and currentInventory.type == 'newdrop' then
			return client.closeInventory()
		end

		if IsNuiFocused() then
			if inv == 'container' and currentInventory.id == PlayerData.inventory[data].metadata.container then
				return client.closeInventory()
			end

			if currentInventory.type == 'drop' and (not data or currentInventory.id == (type(data) == 'table' and data.id or data)) then
				return client.closeInventory()
			end

			if inv ~= 'drop' and inv ~= 'container' then
				return client.closeInventory()
			end
		end
	elseif IsNuiFocused() then
		-- If triggering event from another nui such as qtarget, may need to wait for focus to end
		Wait(100)

		if IsNuiFocused() then return end
	end

	if inv == 'dumpster' and cache.vehicle then
		return lib.notify({ type = 'error', description = shared.locale('inventory_right_access') })
	end

	if canOpenInventory() then
		local left, right

		if inv == 'shop' and invOpen == false then
			left, right = lib.callback.await('ox_inventory:openShop', 200, data)
		elseif invOpen ~= nil then
			if inv == 'policeevidence' then
				local input = lib.inputDialog(shared.locale('police_evidence'), {shared.locale('locker_number')})

				if input then
					---@diagnostic disable-next-line: cast-local-type
					input = tonumber(input[1])
				else
					return lib.notify({ description = shared.locale('locker_no_value'), type = 'error' })
				end

				if type(input) ~= 'number' then
					return lib.notify({ description = shared.locale('locker_must_number'), type = 'error' })
				else
					data = input
				end
			end

			left, right = lib.callback.await('ox_inventory:openInventory', false, inv, data)
		end

		if left then
			if inv ~= 'trunk' and not cache.vehicle then
				Utils.PlayAnim(1000, 'pickup_object', 'putdown_low', 5.0, 1.5, -1, 48, 0.0, 0, 0, 0)
			end

			plyState.invOpen = true
			SetInterval(client.interval, 100)
			SetNuiFocus(true, true)
			SetNuiFocusKeepInput(true)
			if client.screenblur then TriggerScreenblurFadeIn(0) end
			closeTrunk()
			currentInventory = right or defaultInventory
			left.items = PlayerData.inventory
			SendNUIMessage({
				action = 'setupInventory',
				data = {
					leftInventory = left,
					rightInventory = currentInventory
				}
			})

			if not currentInventory.coords and not inv == 'container' then
				currentInventory.coords = GetEntityCoords(cache.ped)
			end

			-- Stash exists (useful for custom stashes)
			return true
		else
			-- Stash does not exist
			if left == false then return false end
			if invOpen == false then lib.notify({ type = 'error', description = shared.locale('inventory_right_access') }) end
			if invOpen then client.closeInventory() end
		end
	elseif invBusy then lib.notify({ type = 'error', description = shared.locale('inventory_player_access') }) end
end
RegisterNetEvent('ox_inventory:openInventory', client.openInventory)
exports('openInventory', client.openInventory)

local Animations = data 'animations'

---@param data table
---@param cb function?
local function useItem(data, cb)
	if invOpen and data.close then client.closeInventory() end

	if not invBusy and not PlayerData.dead and not lib.progressActive() and not IsPedRagdoll(cache.ped) and not IsPedFalling(cache.ped) then
		if currentWeapon and currentWeapon?.timer > 100 then return end

		invBusy = 1
		local result = lib.callback.await('ox_inventory:useItem', 200, data.name, data.slot, PlayerData.inventory[data.slot].metadata)

		if not result then
			Wait(500)
			invBusy = false
			return
		end

		if result and invBusy then
			plyState.invBusy = true
			if data.client then data = data.client end

			if type(data.anim) == 'string' then
				data.anim = Animations.anim[data.anim]
			end

			if data.propTwo then
				data.prop = { data.prop, data.propTwo }
			end

			if data.prop then
				if data.prop[1] then
					for i = 1, #data.prop do
						if type(data.prop) == 'string' then
							data.prop = Animations.prop[data.prop[i]]
						end
					end
				elseif type(data.prop) == 'string' then
					data.prop = Animations.prop[data.prop]
				end
			end

			local success = (not data.usetime or lib.progressBar({
				duration = data.usetime,
				label = data.label or shared.locale('using', result.label),
				useWhileDead = data.useWhileDead,
				canCancel = data.cancel,
				disable = data.disable,
				anim = data.anim or data.scenario,
				prop = data.prop
			})) and not PlayerData.dead

			if success then
				if result.consume and result.consume ~= 0 and not result.component then
					TriggerServerEvent('ox_inventory:removeItem', result.name, result.consume, result.metadata, result.slot, true)
				end

				if data.status and client.setPlayerStatus then
					client.setPlayerStatus(data.status)
				end

				if data.notification then
					lib.notify({ description = data.notification })
				end

				if cb then cb(result) end
				Wait(200)
				plyState.invBusy = false
				return
			end
		end
	end
	if cb then cb(false) end
	Wait(200)
	plyState.invBusy = false
end
AddEventHandler('ox_inventory:item', useItem)
exports('useItem', useItem)

local Items = client.items

---@param slot number
---@return boolean?
local function useSlot(slot)
	if PlayerData.loaded and not PlayerData.dead and not invBusy and not lib.progressActive() then
		local item = PlayerData.inventory[slot]
		if not item then return end

		local data = Items[item.name]
		if not data then return end

		if data.component and not currentWeapon then
			return lib.notify({ type = 'error', description = shared.locale('weapon_hand_required') })
		end

		data.slot = slot

		if item.metadata.container then
			return client.openInventory('container', item.slot)
		elseif data.client then
			if invOpen and data.close then client.closeInventory() end

			if data.export then
				return data.export(data, {name = item.name, slot = item.slot, metadata = item.metadata})
			elseif data.client.event then -- re-add it, so I don't need to deal with morons taking screenshots of errors when using trigger event
				return TriggerEvent(data.client.event, data, {name = item.name, slot = item.slot, metadata = item.metadata})
			end
		end

		if data.effect then
			data:effect({name = item.name, slot = item.slot, metadata = item.metadata})
		elseif data.weapon then
			if EnableWeaponWheel then return end
			useItem(data, function(result)
				if result then
					if currentWeapon?.slot == result.slot then
						currentWeapon = Weapon.Disarm(currentWeapon)
						return
					end

					currentWeapon = Weapon.Equip(item, data)
				end
			end)
		elseif currentWeapon then
			local playerPed = cache.ped
			if data.ammo then
				if EnableWeaponWheel or currentWeapon.metadata.durability <= 0 then return end
				local maxAmmo = GetMaxAmmoInClip(playerPed, currentWeapon.hash, true)
				local currentAmmo = GetAmmoInPedWeapon(playerPed, currentWeapon.hash)

				if currentAmmo ~= maxAmmo and currentAmmo < maxAmmo then
					useItem(data, function(data)
						if data then
							if data.name == currentWeapon.ammo then
								local missingAmmo = 0
								local newAmmo = 0
								missingAmmo = maxAmmo - currentAmmo

								if missingAmmo > data.count then newAmmo = currentAmmo + data.count else newAmmo = maxAmmo end
								if newAmmo < 0 then newAmmo = 0 end

								SetPedAmmo(playerPed, currentWeapon.hash, newAmmo)

								if not cache.vehicle then
									MakePedReload(playerPed)
								else
									lib.disableControls:Add(68)
									RefillAmmoInstantly(playerPed)
								end

								currentWeapon.metadata.ammo = newAmmo
								TriggerServerEvent('ox_inventory:updateWeapon', 'load', currentWeapon.metadata.ammo)

								if cache.vehicle then
									Wait(300)
									lib.disableControls:Remove(68)
								end
							end
						end
					end)
				end
			elseif data.component then
				local components = data.client.component
				local componentType = data.type
				local weaponComponents = PlayerData.inventory[currentWeapon.slot].metadata.components
				-- Checks if the weapon already has the same component type attached
				for componentIndex = 1, #weaponComponents do
					if componentType == Items[weaponComponents[componentIndex]].type then
						-- todo: Update locale?
						return lib.notify({ type = 'error', description = shared.locale('component_has', data.label) })
					end
				end
				for i = 1, #components do
					local component = components[i]

					if DoesWeaponTakeWeaponComponent(currentWeapon.hash, component) then
						if HasPedGotWeaponComponent(playerPed, currentWeapon.hash, component) then
							lib.notify({ type = 'error', description = shared.locale('component_has', data.label) })
						else
							useItem(data, function(data)
								if data then
									GiveWeaponComponentToPed(playerPed, currentWeapon.hash, component)
									table.insert(PlayerData.inventory[currentWeapon.slot].metadata.components, data.name)
									TriggerServerEvent('ox_inventory:updateWeapon', 'component', tostring(data.slot), currentWeapon.slot)
								end
							end)
						end
						return
					end
				end
				lib.notify({ type = 'error', description = shared.locale('component_invalid', data.label) })
			elseif data.allowArmed then
				useItem(data)
			end
		elseif not data.ammo and not data.component then
			useItem(data)
		end
	end
end
exports('useSlot', useSlot)

---@param id number
---@param slot number
local function useButton(id, slot)
	if PlayerData.loaded and not invBusy and not lib.progressActive() then
		local item = PlayerData.inventory[slot]
		if not item then return end

		local data = Items[item.name]
		local buttons = data?.buttons

		if buttons and buttons[id]?.action then
			buttons[id].action(slot)
		end
	end
end

---@param ped number
---@return boolean
local function canOpenTarget(ped)
	return IsPedFatallyInjured(ped)
	or IsEntityPlayingAnim(ped, 'dead', 'dead_a', 3)
	or IsPedCuffed(ped)
	or IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3)
	or IsEntityPlayingAnim(ped, 'missminuteman_1ig_2', 'handsup_base', 3)
	or IsEntityPlayingAnim(ped, 'missminuteman_1ig_2', 'handsup_enter', 3)
	or IsEntityPlayingAnim(ped, 'random@mugging3', 'handsup_standing_base', 3)
end

local function openNearbyInventory()
	if canOpenInventory() then
		local targetId, targetPed = Utils.GetClosestPlayer()

		if targetId and (client.hasGroup(shared.police) or canOpenTarget(targetPed)) then
			Utils.PlayAnim(2000, 'mp_common', 'givetake1_a', 1.0, 1.0, -1, 50, 0.0, 0, 0, 0)
			client.openInventory('player', GetPlayerServerId(targetId))
		end
	end
end
exports('openNearbyInventory', openNearbyInventory)

local currentInstance
local drops, playerCoords
local table = lib.table
local Shops = client.shops
local Inventory = client.inventory

---@todo remove or replace when the bridge module gets restructured
function OnPlayerData(key, val)
	if key ~= 'groups' and key ~= 'ped' and key ~= 'dead' then return end

	if key == 'groups' then
		Inventory.Stashes()
		Inventory.Evidence()
		Shops()
	elseif key == 'dead' and val then
		currentWeapon = Weapon.Disarm(currentWeapon)
		client.closeInventory()
	end

	Utils.WeaponWheel()
end

-- People consistently ignore errors when one of the "modules" failed to load
if not Utils or not Weapon or not Items or not Shops or not Inventory then return end

local function registerCommands()
	RegisterCommand('inv', function()
		if not invOpen then
			local closest = lib.points.closest()

			if closest and closest.currentDistance < 1.2 then
				if closest.inv ~= 'license' and closest.inv ~= 'policeevidence' then
					return client.openInventory(closest.inv or 'drop', { id = closest.invId, type = closest.type })
				end
			end
		end

		client.openInventory()
	end, false)
	RegisterKeyMapping('inv', shared.locale('open_player_inventory'), 'keyboard', client.keys[1])
	TriggerEvent('chat:removeSuggestion', '/inv')

	local Vehicles = data 'vehicles'

	RegisterCommand('inv2', function()
		if IsNuiFocused() then
			return invOpen and client.closeInventory()
		end

		if not invOpen then
			if invBusy then
				return lib.notify({ type = 'error', description = shared.locale('inventory_player_access') })
			else
				if not canOpenInventory() then
					return lib.notify({ type = 'error', description = shared.locale('inventory_player_access') })
				end

				if StashTarget then
					client.openInventory('stash', StashTarget)
				elseif cache.vehicle then
					-- Player is still entering vehicle, so bailout
					if not IsPedInAnyVehicle(cache.ped, false) then return end

					local vehicle = cache.vehicle

					if NetworkGetEntityIsNetworked(vehicle) then
						local vehicleHash = GetEntityModel(vehicle)
						local vehicleClass = GetVehicleClass(vehicle)
						local checkVehicle = Vehicles.Storage[vehicleHash]
						-- No storage or no glovebox
						if (checkVehicle == 0 or checkVehicle == 2) or (not Vehicles.glovebox[vehicleClass] and not Vehicles.glovebox.models[vehicleHash]) then return end

						local plate = client.trimplate and string.strtrim(GetVehicleNumberPlateText(vehicle)) or GetVehicleNumberPlateText(vehicle)
						client.openInventory('glovebox', {id = 'glove'..plate, class = vehicleClass, model = vehicleHash, netid = NetworkGetNetworkIdFromEntity(vehicle) })

						while true do
							Wait(100)
							if not invOpen then break
							elseif not cache.vehicle then
								client.closeInventory()
								break
							end
						end
					end
				else
					local entity, type = Utils.Raycast()
					if not entity then return end
					local vehicle, position

					if not shared.qtarget then
						if type == 2 then vehicle, position = entity, GetEntityCoords(entity)
						elseif type == 3 and table.contains(Inventory.Dumpsters, GetEntityModel(entity)) then
							local netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity)

							if not netId then
								NetworkRegisterEntityAsNetworked(entity)
								netId = NetworkGetNetworkIdFromEntity(entity)
								NetworkUseHighPrecisionBlending(netId, false)
								SetNetworkIdExistsOnAllMachines(netId, true)
								SetNetworkIdCanMigrate(netId, true)
							end

							return client.openInventory('dumpster', 'dumpster'..netId)
						end
					elseif type == 2 then
						vehicle, position = entity, GetEntityCoords(entity)
					else return end

					if not vehicle then return end

					local lastVehicle
					local vehicleHash = GetEntityModel(vehicle)
					local vehicleClass = GetVehicleClass(vehicle)
					local checkVehicle = Vehicles.Storage[vehicleHash]
					-- No storage or no glovebox
					if (checkVehicle == 0 or checkVehicle == 1) or (not Vehicles.trunk[vehicleClass] and not Vehicles.trunk.models[vehicleHash]) then return end

					if #(playerCoords - position) < 6 and NetworkGetEntityIsNetworked(vehicle) then
						local locked = GetVehicleDoorLockStatus(vehicle)

						if locked == 0 or locked == 1 then
							local open, vehBone

							if checkVehicle == nil then -- No data, normal trunk
								open, vehBone = 5, GetEntityBoneIndexByName(vehicle, 'boot')
							elseif checkVehicle == 3 then -- Trunk in hood
								open, vehBone = 4, GetEntityBoneIndexByName(vehicle, 'bonnet')
							else -- No storage or no trunk
								return
							end

							if vehBone == -1 then vehBone = GetEntityBoneIndexByName(vehicle, Vehicles.trunk.boneIndex[vehicleHash] or 'platelight') end

							position = GetWorldPositionOfEntityBone(vehicle, vehBone)
							local distance = #(playerCoords - position)
							local closeToVehicle = distance < 2 and (open == 5 and (checkVehicle == nil and true or 2) or open == 4)

							if closeToVehicle then
								local plate = client.trimplate and string.strtrim(GetVehicleNumberPlateText(vehicle)) or GetVehicleNumberPlateText(vehicle)
								TaskTurnPedToFaceCoord(cache.ped, position.x, position.y, position.z, 0)
								lastVehicle = vehicle
								client.openInventory('trunk', {id='trunk'..plate, class = vehicleClass, model = vehicleHash, netid = NetworkGetNetworkIdFromEntity(vehicle)})
								local timeout = 20
								repeat Wait(50)
									timeout -= 1
								until (currentInventory and currentInventory.type == 'trunk') or timeout == 0

								if timeout == 0 then
									closeToVehicle, lastVehicle = false, nil
									return
								end

								SetVehicleDoorOpen(vehicle, open, false, false)
								Wait(200)
								Utils.PlayAnim(0, 'anim@heists@prison_heiststation@cop_reactions', 'cop_b_idle', 3.0, 3.0, -1, 49, 0.0, 0, 0, 0)
								currentInventory.entity = lastVehicle
								currentInventory.door = open

								while true do
									Wait(50)

									if closeToVehicle and invOpen then
										position = GetWorldPositionOfEntityBone(vehicle, vehBone)

										if #(GetEntityCoords(cache.ped) - position) >= 2 or not DoesEntityExist(vehicle) then
											break
										else TaskTurnPedToFaceCoord(cache.ped, position.x, position.y, position.z, 0) end
									else break end
								end

								if lastVehicle then client.closeInventory() end
							end
						else lib.notify({ type = 'error', description = shared.locale('vehicle_locked') }) end
					end
				end
			end
		else return client.closeInventory()
		end
	end, false)
	RegisterKeyMapping('inv2', shared.locale('open_secondary_inventory'), 'keyboard', client.keys[2])
	TriggerEvent('chat:removeSuggestion', '/inv2')

	RegisterCommand('reload', function()
		if currentWeapon?.ammo then
			if currentWeapon.metadata.durability > 0 then
				local ammo = Inventory.Search(1, currentWeapon.ammo)

				if ammo and ammo[1] then
					useSlot(ammo[1].slot)
				end
			else
				lib.notify({ type = 'error', description = shared.locale('no_durability', currentWeapon.label) })
			end
		end
	end, false)
	RegisterKeyMapping('reload', shared.locale('reload_weapon'), 'keyboard', 'r')
	TriggerEvent('chat:removeSuggestion', '/reload')

	RegisterCommand('hotbar', function()
		if not EnableWeaponWheel and not IsPauseMenuActive() and not IsNuiFocused() then
			SendNUIMessage({ action = 'toggleHotbar' })
		end
	end, false)
	RegisterKeyMapping('hotbar', shared.locale('disable_hotbar'), 'keyboard', client.keys[3])
	TriggerEvent('chat:removeSuggestion', '/hotbar')

	RegisterCommand('steal', function()
		openNearbyInventory()
	end, false)

	for i = 1, 5 do
		local hotkey = ('hotkey%s'):format(i)

		RegisterCommand(hotkey, function()
			if not invOpen and not IsPauseMenuActive() and not IsNuiFocused() then
				CreateThread(function() useSlot(i) end)
			end
		end, false)

		---@diagnostic disable-next-line: param-type-mismatch
		RegisterKeyMapping(hotkey, shared.locale('use_hotbar', i), 'keyboard', i)
		TriggerEvent('chat:removeSuggestion', '/'..hotkey)
	end

end

function client.closeInventory(server)
	-- because somehow people are triggering this when the inventory isn't loaded
	-- and they're incapable of debugging, and I can't repro on a fresh install
	if not client.interval then return end

	if invOpen then
		invOpen = nil
		SetNuiFocus(false, false)
		SetNuiFocusKeepInput(false)
		TriggerScreenblurFadeOut(0)
		closeTrunk()
		SendNUIMessage({ action = 'closeInventory' })
		SetInterval(client.interval, 200)
		Wait(200)

		if not server and currentInventory then
			TriggerServerEvent('ox_inventory:closeInventory')
		end

		currentInventory = nil
		plyState.invOpen = false
		defaultInventory.coords = nil
	end
end

RegisterNetEvent('ox_inventory:closeInventory', client.closeInventory)

local function updateInventory(items, weight)
	-- todo: combine iterators
	local changes = {}
	local itemCount = {}
	-- swapslots
	if type(weight) == 'number' then
		for slot, v in pairs(items) do
			local item = PlayerData.inventory[slot]

			if item then
				itemCount[item.name] = (itemCount[item.name] or 0) - item.count
			end

			if v then
				itemCount[v.name] = (itemCount[v.name] or 0) + v.count
			end

			PlayerData.inventory[slot] = v and v or nil
			changes[slot] = v
		end
		client.setPlayerData('weight', weight)
	else
		for i = 1, #items do
			local v = items[i].item
			local item = PlayerData.inventory[v.slot]

			if item?.name then
				itemCount[item.name] = (itemCount[item.name] or 0) - item.count
			end

			if v.count then
				itemCount[v.name] = (itemCount[v.name] or 0) + v.count
			end

			changes[v.slot] = v.count and v or false
			if not v.count then v.name = nil end
			PlayerData.inventory[v.slot] = v.name and v or nil
		end
		client.setPlayerData('weight', weight.left)
		SendNUIMessage({ action = 'refreshSlots', data = items })
	end

	for item, count in pairs(itemCount) do
		local data = Items[item]

		if count < 0 then
			data.count += count

			if shared.framework == 'esx' then
				TriggerEvent('esx:removeInventoryItem', data.name, data.count)
			else
				TriggerEvent('ox_inventory:itemCount', data.name, data.count)
			end

			if data.client?.remove then
				data.client.remove(data.count)
			end
		elseif count > 0 then
			data.count += count

			if shared.framework == 'esx' then
				TriggerEvent('esx:addInventoryItem', data.name, data.count)
			else
				TriggerEvent('ox_inventory:itemCount', data.name, data.count)
			end

			if data.client?.add then
				data.client.add(data.count)
			end
		end
	end

	client.setPlayerData('inventory', PlayerData.inventory)
	TriggerEvent('ox_inventory:updateInventory', changes)
end

RegisterNetEvent('ox_inventory:updateSlots', function(items, weights, count, removed)
	if count then
		local item = items[1].item

		if not item.name then
			item = PlayerData.inventory[item.slot]
		end

		Utils.ItemNotify({item.metadata?.label or item.label, item.metadata?.image or item.name, removed and 'ui_removed' or 'ui_added', count})
	end

	updateInventory(items, weights)
end)

RegisterNetEvent('ox_inventory:inventoryReturned', function(data)
	lib.notify({ description = shared.locale('items_returned') })
	if currentWeapon then currentWeapon = Weapon.Disarm(currentWeapon) end
	client.closeInventory()
	PlayerData.inventory = data[1]
	client.setPlayerData('inventory', data[1])
	client.setPlayerData('weight', data[3])
end)

RegisterNetEvent('ox_inventory:inventoryConfiscated', function(message)
	if message then lib.notify({ description = shared.locale('items_confiscated') }) end
	if currentWeapon then currentWeapon = Weapon.Disarm(currentWeapon) end
	client.closeInventory()
	table.wipe(PlayerData.inventory)
	client.setPlayerData('weight', 0)
end)

local function nearbyDrop(self)
	if not self.instance or self.instance == currentInstance then
		---@diagnostic disable-next-line: param-type-mismatch
		DrawMarker(2, self.coords.x, self.coords.y, self.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.2, 0.15, 150, 30, 30, 222, false, false, 0, true, false, false, false)
	end
end

RegisterNetEvent('ox_inventory:createDrop', function(drop, data, owner, slot)
	if drops then
		drops[drop] = lib.points.new({
			coords = data.coords,
			distance = 16,
			invId = drop,
			instance = data.instance,
			nearby = nearbyDrop
		})
	end

	if owner == PlayerData.source then
		if currentWeapon?.slot == slot then
			currentWeapon = Weapon.Disarm(currentWeapon)
		end

		if invOpen and #(GetEntityCoords(cache.ped) - data.coords) <= 1 then
			if not cache.vehicle then
				client.openInventory('drop', drop)
			else
				SendNUIMessage({
					action = 'setupInventory',
					data = { rightInventory = currentInventory }
				})
			end
		end
	end
end)

RegisterNetEvent('ox_inventory:removeDrop', function(id)
	if drops then
		drops[id]:remove()
		drops[id] = nil
	end
end)

local uiLoaded = false

---@type function?
local function setStateBagHandler(stateId)
	AddStateBagChangeHandler('invOpen', stateId, function(_, _, value)
		invOpen = value
	end)

	AddStateBagChangeHandler('invBusy', stateId, function(_, _, value)
		invBusy = value

		if value then
			lib.disableControls:Add(23, 25, 36, 68, 263)
		else
			lib.disableControls:Remove(23, 25, 36, 68, 263)
		end
	end)

	AddStateBagChangeHandler('instance', stateId, function(_, _, value)
		currentInstance = value
	end)

	AddStateBagChangeHandler('dead', stateId, function(_, _, value)
		Utils.WeaponWheel()
		PlayerData.dead = value
	end)

	setStateBagHandler = nil
end

lib.onCache('ped', function()
	Utils.WeaponWheel()
end)

lib.onCache('seat', function(seat)
	if seat then
		if DoesVehicleHaveWeapons(cache.vehicle) then
			return Utils.WeaponWheel(true)
		end
	end

	Utils.WeaponWheel(false)
end)

RegisterNetEvent('ox_inventory:setPlayerInventory', function(currentDrops, inventory, weight, player, source)
	PlayerData = player
	PlayerData.id = cache.playerId
	PlayerData.source = source

	setmetatable(PlayerData, {
		__index = function(self, key)
			if key == 'ped' then
				return PlayerPedId()
			end
		end
	})

	if setStateBagHandler then setStateBagHandler(('player:%s'):format(source)) end

	for _, data in pairs(inventory) do
		local item = Items[data.name]

		if item then
			item.count += data.count
		end
	end

	local phone = Items.phone

	if phone and phone.count < 1 then
		pcall(function()
			return exports.npwd:setPhoneDisabled(true)
		end)
	end

	client.setPlayerData('inventory', inventory)
	client.setPlayerData('weight', weight)
	currentWeapon = nil
	Weapon.ClearAll()

	local ItemData = table.create(0, #Items)

	for _, v in pairs(Items) do
		local buttons = {}

		if v.buttons then
			for id, button in pairs(v.buttons) do
				buttons[id] = button.label
			end
		end

		ItemData[v.name] = {
			label = v.label,
			stack = v.stack,
			close = v.close,
			description = v.description,
			buttons = buttons
		}
	end

	local locales = {}

	for k, v in pairs(shared.locale()) do
		if k:find('ui_') or k == '$' then
			locales[k] = v
		end
	end

	drops = currentDrops

	for k, v in pairs(currentDrops) do
		drops[k] = lib.points.new({
			coords = v.coords,
			distance = 16,
			invId = k,
			instance = v.instance,
			nearby = nearbyDrop
		})
	end

	while not uiLoaded do Wait(50) end

	SendNUIMessage({
		action = 'init',
		data = {
			locale = locales,
			items = ItemData,
			leftInventory = {
				id = cache.playerId,
				slots = shared.playerslots,
				items = PlayerData.inventory,
				maxWeight = shared.playerweight,
			},
			imagepath = GetConvar('inventory:imagepath', 'nui://ox_inventory/web/images')
		}
	})

	PlayerData.loaded = true

	Shops()
	Inventory.Stashes()
	Inventory.Evidence()
	registerCommands()
	TriggerEvent('ox_inventory:updateInventory', PlayerData.inventory)
	lib.notify({ description = shared.locale('inventory_setup') })

	local function nearbyLicense(self)
		---@diagnostic disable-next-line: param-type-mismatch
		DrawMarker(2, self.coords.x, self.coords.y, self.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.2, 0.15, 30, 150, 30, 222, false, false, 0, true, false, false, false)

		if self.currentDistance < 1.2 and lib.points.closest().id == self.id and IsControlJustReleased(0, 38) then
			lib.callback('ox_inventory:buyLicense', 1000, function(success, message)
				if success then
					lib.notify ({ description = shared.locale(message) })
				elseif success == false then
					lib.notify ({ type = 'error', description = shared.locale(message) })
				end
			end, self.invId)
		end
	end

	for id, data in pairs(data('licenses')) do
		lib.points.new({
			coords = data.coords,
			distance = 16,
			inv = 'license',
			type = data.name,
			invId = id,
			nearby = nearbyLicense
		})
	end

	client.interval = SetInterval(function()
		local playerPed = cache.ped

		if invOpen == false then
			playerCoords = GetEntityCoords(playerPed)

			if currentWeapon and IsPedUsingActionMode(cache.ped) then
				SetPedUsingActionMode(cache.ped, false, -1, 'DEFAULT_ACTION')
			end

		elseif invOpen == true then
			if not canOpenInventory() then
				client.closeInventory()
			else
				playerCoords = GetEntityCoords(playerPed)
				if currentInventory then

					if currentInventory.type == 'otherplayer' then
						local id = GetPlayerFromServerId(currentInventory.id)
						local ped = GetPlayerPed(id)
						local pedCoords = GetEntityCoords(ped)

						if not id or #(playerCoords - pedCoords) > 1.8 or not (client.hasGroup(shared.police) or canOpenTarget(ped)) then
							client.closeInventory()
							lib.notify({ type = 'error', description = shared.locale('inventory_lost_access') })
						else
							TaskTurnPedToFaceCoord(playerPed, pedCoords.x, pedCoords.y, pedCoords.z, 50)
						end

					elseif currentInventory.coords and (#(playerCoords - currentInventory.coords) > (currentInventory.distance or 2.0) or canOpenTarget(playerPed)) then
						client.closeInventory()
						lib.notify({ type = 'error', description = shared.locale('inventory_lost_access') })
					end
				end
			end
		end

		local weaponHash = GetSelectedPedWeapon(playerPed)

		if currentWeapon and weaponHash ~= currentWeapon.hash then
			TriggerServerEvent('ox_inventory:updateWeapon')
			currentWeapon = Weapon.Disarm(currentWeapon, true)

			if weaponHash == `WEAPON_HANDCUFFS` or weaponHash == `WEAPON_GARBAGEBAG` or weaponHash == `WEAPON_BRIEFCASE` or weaponHash == `WEAPON_BRIEFCASE_02` then
				SetCurrentPedWeapon(cache.ped, weaponHash --[[@as number]], true)
			end
		end

		if client.parachute and GetPedParachuteState(playerPed) ~= -1 then
			Utils.DeleteObject(client.parachute)
			client.parachute = false
		end
	end, 200)

	local playerId = cache.playerId
	local EnableKeys = client.enablekeys
	local DisablePlayerVehicleRewards = DisablePlayerVehicleRewards
	local DisableAllControlActions = DisableAllControlActions
	local HideHudAndRadarThisFrame = HideHudAndRadarThisFrame
	local EnableControlAction = EnableControlAction
	local disableControls = lib.disableControls
	local DisablePlayerFiring = DisablePlayerFiring
	local HudWeaponWheelIgnoreSelection = HudWeaponWheelIgnoreSelection
	local DisableControlAction = DisableControlAction

	client.tick = SetInterval(function()
		DisablePlayerVehicleRewards(playerId)

		if invOpen then
			DisableAllControlActions(0)
			HideHudAndRadarThisFrame()

			for i = 1, #EnableKeys do
				EnableControlAction(0, EnableKeys[i], true)
			end

			if currentInventory.type == 'newdrop' then
				EnableControlAction(0, 30, true)
				EnableControlAction(0, 31, true)
			end
		else
			local playerPed = cache.ped
			disableControls()

			if invBusy == 1 or IsPedCuffed(playerPed) then
				DisablePlayerFiring(playerId, true)
			end

			if not EnableWeaponWheel then
				HudWeaponWheelIgnoreSelection()
				DisableControlAction(0, 37, true)
			end

			if currentWeapon then
				DisableControlAction(0, 80, true)
				DisableControlAction(0, 140, true)

				if currentWeapon.metadata.durability <= 0 then
					DisablePlayerFiring(playerId, true)
				elseif client.aimedfiring and not currentWeapon.melee and not IsPlayerFreeAiming(playerId) then
					DisablePlayerFiring(playerId, true)
				end

				if not invBusy and currentWeapon.timer ~= 0 and currentWeapon.timer < GetGameTimer() then
					currentWeapon.timer = 0
					if currentWeapon.metadata.ammo then
						TriggerServerEvent('ox_inventory:updateWeapon', 'ammo', currentWeapon.metadata.ammo)
					elseif currentWeapon.metadata.durability then
						TriggerServerEvent('ox_inventory:updateWeapon', 'melee', currentWeapon.melee)
						currentWeapon.melee = 0
					end
				elseif currentWeapon.metadata.ammo then
					if IsPedShooting(playerPed) then
						local currentAmmo

						if currentWeapon.hash == `WEAPON_PETROLCAN` or currentWeapon.hash == `WEAPON_HAZARDCAN` or currentWeapon.hash == `WEAPON_FERTILIZERCAN` or currentWeapon.hash == `WEAPON_FIREEXTINGUISHER` then
							currentAmmo = currentWeapon.metadata.ammo - 0.05

							if currentAmmo <= 0 then
								SetPedInfiniteAmmo(playerPed, false, currentWeapon.hash)
							end

						else currentAmmo = GetAmmoInPedWeapon(playerPed, currentWeapon.hash) end
						currentWeapon.metadata.ammo = (currentWeapon.metadata.ammo < currentAmmo) and 0 or currentAmmo

						if currentAmmo <= 0 then
							ClearPedTasks(playerPed)
							SetCurrentPedWeapon(playerPed, currentWeapon.hash, true)
							SetPedCurrentWeaponVisible(playerPed, true, false, false, false)
							if currentWeapon?.ammo and client.autoreload and not lib.progressActive() and not IsPedRagdoll(playerPed) and not IsPedFalling(playerPed) then
								currentWeapon.timer = 0
								local ammo = Inventory.Search(1, currentWeapon.ammo)

								if ammo and ammo[1] then
									TriggerServerEvent('ox_inventory:updateWeapon', 'ammo', currentWeapon.metadata.ammo)
									useSlot(ammo[1].slot)
								end
							else currentWeapon.timer = GetGameTimer() + 400 end
						else currentWeapon.timer = GetGameTimer() + 400 end
					end
				elseif IsControlJustReleased(0, 24) then
					if currentWeapon.throwable then
						plyState.invBusy = true
						local weapon = currentWeapon

						SetTimeout(700, function()
							ClearPedSecondaryTask(playerPed)
							RemoveWeaponFromPed(playerPed, weapon.hash)
							TriggerServerEvent('ox_inventory:updateWeapon', 'throw')
							currentWeapon = nil
							TriggerEvent('ox_inventory:currentWeapon')
							plyState.invBusy = false
						end)

					elseif IsPedPerformingMeleeAction(playerPed) then
						currentWeapon.melee += 1
						currentWeapon.timer = GetGameTimer() + 400
					end
				end
			end
		end
	end)

	plyState:set('invBusy', false, false)
	plyState:set('invOpen', false, false)
	collectgarbage('collect')
end)

AddEventHandler('onResourceStop', function(resourceName)
	if shared.resource == resourceName then
		if client.parachute then
			Utils.DeleteObject(client.parachute)
		end

		if invOpen then
			SetNuiFocus(false, false)
			SetNuiFocusKeepInput(false)
			TriggerScreenblurFadeOut(0)
		end
	end
end)

RegisterNetEvent('ox_inventory:viewInventory', function(data)
	if data and invOpen == false then
		data.type = 'admin'
		plyState.invOpen = true
		currentInventory = data
		SendNUIMessage({
			action = 'setupInventory',
			data = {
				rightInventory = currentInventory,
			}
		})
		SetNuiFocus(true, true)
	end
end)

RegisterNUICallback('uiLoaded', function(_, cb)
	uiLoaded = true
	cb(1)
end)

RegisterNUICallback('removeComponent', function(data, cb)
	cb(1)
	if currentWeapon then
		if data.slot ~= currentWeapon.slot then return lib.notify({ type = 'error', description = shared.locale('weapon_hand_wrong') }) end
		local itemSlot = PlayerData.inventory[currentWeapon.slot]
		for _, component in pairs(Items[data.component].client.component) do
			if HasPedGotWeaponComponent(cache.ped, currentWeapon.hash, component) then
				RemoveWeaponComponentFromPed(cache.ped, currentWeapon.hash, component)
				for k, v in pairs(itemSlot.metadata.components) do
					if v == data.component then
						table.remove(itemSlot.metadata.components, k)
						TriggerServerEvent('ox_inventory:updateWeapon', 'component', k)
						break
					end
				end
			end
		end
	else
		TriggerServerEvent('ox_inventory:updateWeapon', 'component', data)
	end
end)

RegisterNUICallback('useItem', function(slot, cb)
	useSlot(slot --[[@as number]])
	cb(1)
end)

RegisterNUICallback('giveItem', function(data, cb)
	cb(1)
	local target

	if client.giveplayerlist then
		local nearbyPlayers = lib.getNearbyPlayers(GetEntityCoords(cache.ped), 2.0)

		if #nearbyPlayers == 0 then return end

		for i = 1, #nearbyPlayers do
			local option = nearbyPlayers[i]
			local playerName = GetPlayerName(option.id)
			option.id = GetPlayerServerId(option.id)
			option.label = ('[%s] %s'):format(option.id, playerName)
			nearbyPlayers[i] = option
		end

		local p = promise.new()

		lib.registerMenu({
			id = 'ox_inventory:givePlayerList',
			title = 'Give item',
			options = nearbyPlayers,
			onClose = function() p:resolve() end,
		}, function(selected) p:resolve(selected and nearbyPlayers[selected].id) end)
		lib.showMenu('ox_inventory:givePlayerList')

		target = Citizen.Await(p)
	elseif cache.vehicle then
		local seats = GetVehicleMaxNumberOfPassengers(cache.vehicle) - 1

		if seats >= 0 then
			local passenger = GetPedInVehicleSeat(cache.vehicle, cache.seat - 2 * (cache.seat % 2) + 1)

			if passenger ~= 0 then
				target = GetPlayerServerId(NetworkGetPlayerIndexFromPed(passenger))
			end
		end
	else
		local entity = Utils.Raycast(12)

		if entity and IsPedAPlayer(entity) and #(GetEntityCoords(cache.ped, true) - GetEntityCoords(entity, true)) < 2.0 then
			target = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
			Utils.PlayAnim(2000, 'mp_common', 'givetake1_a', 1.0, 1.0, -1, 50, 0.0, 0, 0, 0)
		end
	end

	if target then
		TriggerServerEvent('ox_inventory:giveItem', data.slot, target, data.count)

		if data.slot == currentWeapon?.slot then
			currentWeapon = Weapon.Disarm(currentWeapon)
		end
	end
end)

RegisterNUICallback('useButton', function(data, cb)
	useButton(data.id, data.slot)
	cb(1)
end)

RegisterNUICallback('exit', function(_, cb)
	client.closeInventory()
	cb(1)
end)

---Synchronise and validate all item movement between the NUI and server.
RegisterNUICallback('swapItems', function(data, cb)
	if data.toType == 'newdrop' and cache.vehicle then
        return cb(false)
    end

	if currentInstance then
		data.instance = currentInstance
	end

	if currentWeapon and data.fromType ~= data.toType then
		if (data.fromType == 'player' and data.fromSlot == currentWeapon.slot) or (data.toType == 'player' and data.toSlot == currentWeapon.slot) then
			currentWeapon = Weapon.Disarm(currentWeapon, true)
		end
	end

	local success, response, weaponSlot = lib.callback.await('ox_inventory:swapItems', false, data)

	if success then
		if response then
			updateInventory(response.items, response.weight)

			if weaponSlot and currentWeapon then
				currentWeapon.slot = weaponSlot
				TriggerEvent('ox_inventory:currentWeapon', currentWeapon)
			end
		end
	elseif response then
		lib.notify({ type = 'error', description = shared.locale(response) })
	end

	if data.toType == 'newdrop' then
		Wait(50)
	end

	cb(success or false)
end)

RegisterNUICallback('buyItem', function(data, cb)
	local response, data, message = lib.callback.await('ox_inventory:buyItem', 100, data)
	if data then
		PlayerData.inventory[data[1]] = data[2]
		client.setPlayerData('inventory', PlayerData.inventory)
		client.setPlayerData('weight', data[4])
		SendNUIMessage({ action = 'refreshSlots', data = data[3] and {{item = data[2]}, {item = data[3], inventory = 'shop'}} or {item = data[2]}})
	end

	if message then
		lib.notify(message)
	end

	cb(response)
end)
