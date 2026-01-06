local ForestFire = {}
ForestFire.Functions = {}
ForestFire.Events = {}

local _settings = {
	windInfluenceScale = 10, --How much the wind influences the fire
	igniteProbabilityDropOff = 30, --How quickly probability drops off
	fireRange = 50, --studs
	timeBetweenSpread = 25, --Seconds between fire spreads
}

local _services = {
	collectionSerivce = game:GetService("CollectionService")
}

--Types
----------------------------------------------------

----------------------------------------------------

--Utility Functions
----------------------------------------------------
local function deepCopy(obj) --Creates a deepcopy of an object
	if type(obj) ~= "table" then
		return obj
	end

	local copy = {}

	for key, value in pairs(obj) do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end

	return copy
end

local function waitInAsync(time: number) --Wait asynchoronously
	task.synchronize()
	task.wait(time)
	task.desynchronize()
end

local function findTreeParent(item) --Find the parent tree of a part, as long as the tree is a "FireTree"
	local suspectModelTree
	local tree

	if item:IsA("Model") then
		suspectModelTree = item
	else
		suspectModelTree = item:FindFirstAncestorWhichIsA("Model")
	end

	if suspectModelTree then
		local tags = suspectModelTree:GetTags()

		if table.find(tags, "FireTree") then
			tree = suspectModelTree
		end
	end

	return tree
end

local function createFire(position: Vector3, parent: Model) --Spawn the fire instance
	task.synchronize()
	local fire = Instance.new("Fire")
	fire.Size = 30
	fire.Heat = 10

	local fireBlock = Instance.new("Part")
	fireBlock.Transparency = 1
	fireBlock.Anchored = true
	fireBlock.CanCollide = false
	fireBlock.Size = Vector3.new(0.1, 0.1, 0.1)
	fireBlock.Position = position

	fire.Parent = fireBlock
	fireBlock.Parent = parent

	task.desynchronize()
end

----------------------------------------------------

--Events
----------------------------------------------------

----------------------------------------------------

--Functions
----------------------------------------------------
ForestFire.Functions.calculateProbability = {
	load = false,
	callback = function(entity1Position: Vector3, entity2Position: Vector3)
		local globalWind = workspace.GlobalWind --Wind vector
		local connectingVector = entity2Position - entity1Position --Vector between the two entities
		local distance = connectingVector.Magnitude --Distance between the two entities

		if globalWind == Vector3.new(0, 0, 0) then
			globalWind = Vector3.new(1, 1, 1) --Make wind vector 1 if it's 0 since maths
		end

		task.desynchronize()

		--@native
		local function calculate()
			local exponentOfDistanceAndScale = math.exp(-(distance / _settings.igniteProbabilityDropOff)) --e^-(distance/dropOff)
			local multiplier = 1 + _settings.windInfluenceScale --Create a multiplier
			local probability = (exponentOfDistanceAndScale / (1 + exponentOfDistanceAndScale)) * multiplier --Probability of spread

			return probability
		end

		task.synchronize()

		return calculate()
	end,
}

ForestFire.Functions.new = { --Create a new fire
	load = false,
	callback = function(object: Model | BasePart | UnionOperation | Vector3)
		task.desynchronize()
		local function getPartsNearLocation(location: Vector3) --Get all the parts nearby
			local parts = workspace:GetPartBoundsInRadius(location, _settings.fireRange)

			return parts
		end
		
		if typeof(object) == "Vector3" then --If the object is a vector, get parts in that area
			local parts = getPartsNearLocation(object)
			local part = parts[1]

			if part then
				ForestFire.Functions.new.callback(part) --If there's a part, make fire
			end
		else
			local tree = findTreeParent(object) --Get the tree
			
			local function getProbabilityOfSpread(entity1: Vector3, parts: { BasePart | UnionOperation | Model })
				local probabilities = {}
	
				for _, part in pairs(parts) do --Go through all parts, calculate probability of spread
					local position
	
					if part.Position then
						position = part.Position
					elseif part:IsA("Model") then
						position = part.WorldPivot
					end
	
					local probability = ForestFire.Functions.calculateProbability.callback(entity1, position)
					table.insert(probabilities, {
						entity = part,
						prob = probability,
					})
	
					waitInAsync(0)
				end
	
				return probabilities
			end

			if tree and not tree:FindFirstChildWhichIsA("Fire", true) then --If a tree and not on fire
				local loop

				_services.collectionSerivce:RemoveTag(tree, "FireTree") --Stop the tree catching fire more
	
				loop = task.spawn(function()
					task.synchronize()
					
					while task.wait(_settings.timeBetweenSpread) do --Wait the tick
						task.desynchronize()
						local location
	
						--Get a location
						if object:IsA("Model") then
							location = object.WorldPivot.Position
						elseif object:IsA("BasePart") or object:IsA("UnionOperation") or object.Position ~= nil then
							location = object.Position
						end
						
						createFire(location, tree) --Make fire
	
						warn("Fire at", location, object) --Debug
	
						local nearParts = getPartsNearLocation(location) --Find parts nearby 
	
						if #nearParts > 0 then --If there are parts nearby
							local probabilities = getProbabilityOfSpread(location, nearParts) --Get the probabilities
	
							for _, probabilityTable in pairs(probabilities) do
								local r = math.random(0, 1) --Random value
								local willSpread = probabilityTable.prob > r --If the probability is greater than random
								local newTree = findTreeParent(probabilityTable.entity) --Find the tree
	
								if willSpread and newTree and not newTree:FindFirstChildWhichIsA("Fire", true) then --If you can spread and there isn't fire
									waitInAsync(_settings.timeBetweenSpread * math.random(0.75, 3)) --Wait some random time, makes it seem more natural
									ForestFire.Functions.new.callback(probabilityTable.entity) --Make new fire
								end
								waitInAsync(0)
							end
						end
	
						--Time for fire to burn out
						task.spawn(function()
							waitInAsync(_settings.timeBetweenSpread * math.random(0.3, 1.3))
							task.cancel(loop)
							task.synchronize()
							tree:Destroy()
						end)
					end
				end)
			end
		end
	end,
}

----------------------------------------------------

return ForestFire

--[[

'##::::'##::::'###:::::'######::'########:'########:'########:::::'##:::'########::'#######::'##::::::::
 ###::'###:::'## ##:::'##... ##:... ##..:: ##.....:: ##.... ##::'####::: ##..  ##:'##.... ##: ##:::'##::
 ####'####::'##:. ##:: ##:::..::::: ##:::: ##::::::: ##:::: ##::.. ##:::..:: ##::: ##:::: ##: ##::: ##::
 ## ### ##:'##:::. ##:. ######::::: ##:::: ######::: ########::::: ##:::::: ##::::: ########: ##::: ##::
 ##. #: ##: #########::..... ##:::: ##:::: ##...:::: ##.. ##:::::: ##::::: ##::::::...... ##: #########:
 ##:.:: ##: ##.... ##:'##::: ##:::: ##:::: ##::::::: ##::. ##::::: ##::::: ##:::::'##:::: ##:...... ##::
 ##:::: ##: ##:::: ##:. ######::::: ##:::: ########: ##:::. ##::'######::: ##:::::. #######:::::::: ##::
..:::::..::..:::::..:::......::::::..:::::........::..:::::..:::......::::..:::::::.......:::::::::..:::

]]
