# Draft
Immer-like module for handling immutable state. Made for Luau. Stable but not production ready. Needs lots of refactoring and testing. :(

## Introduction
Like Immer, handling immutable state is simplified to a single `Produce` function. `Produce` takes your previous state and provides a table. This table acts as a proxy of your previous state, meaning changes made to this table won't influence your previous state.

This means that you don't have to deal with copying tables and you aren't constrained to using special immutable data structures.

Draft will also automatically freeze your state as it goes. If you handle your state entirely using Draft, it will always be completely immutable.

Basic example:
```lua
local Produce = require(...Draft).Produce

local oldState = {
	foo = 1,
	bar = {
		a = 2,
		b = {
			c = 3,
			d = 4
		}
	}
}

local newState = Produce(oldState, function(Draft, table)
	Draft.foo = 2
	
	local b = Draft.bar.b
	
	table.Iterate(b, function(key)
		b[key] *= 2
	end)

	table.insert(Draft, {1, 2, 3})
end)
```
Iterating with numeric for works as normal. Inverting a 2d array:
```lua
local Produce = require(...Draft).Produce

local oldState = {}
for y = 1, 10 do
	table.insert(oldState, table.create(10, math.random(0, 1)))
end

local newState = Produce(oldState, function(Draft)
	for y = 1, 10 do
		local row = Draft[y]
		for x = 1, 10 do
			row[x] = (row[x] == 1 and 0 or 1)
		end
	end
end)
```
When you're dealing with flat or shallow tables, this may appear to be overkill. It probably is! Draft is particularly advantageous, however, when you want to make changes to deeply nested layers of your state. 

Consider the following:
```lua
local Items = {
	Cool_Gun = {
		ID = 1,
		Name = "Cool Gun 😎",
		Settings = {
			Damage = 60,
			Dropoff = 100,
			FireRate = 10,
			Magazine = 30
		}
	},
	Epic_Sword = {
		ID = 2,
		Name = "EPIC SWORD :O",
		Settings = {
			Damage = 60
		}
	},
	Lame_Flashlight = {
		ID = 3,
		Name = "flashlight...",
		Settings = {
			Brightness = 0.1,
			Distance = 10
		}
	}
}

local PlayerData = {
	[1337] = {
		Username = "cornprices",
		Health = 100,
		Stats = {
			Level = 100,
			Points = 100000
		},
		Inventory = {
			Items.Cool_Gun,
			Items.Lame_Flashlight
		}
	},
	...
}
```
Modifying data anywhere deep within `PlayerData` without mutating it is hard. You could deep clone it, but that also clones data that you aren't touching. You could shallow clone everything _except_ for what you want to change, but that gets convoluted and confusing as you get deeper in to the structure or if you want to make more than one change. You could use a library like Llama (great in the majority of cases), but as you get in to deeper layers, that too becomes convoluted.

With Draft it's easy. You make changes as if you were making them directly to the original table.
```lua
local function GodMode(ID)
	return Produce(PlayerData, function(Draft, table)
		local Player = Draft[ID]
		
		Player.Health = math.huge
		Player.Stats.Level = math.huge
		Player.Stats.Points = math.huge
		
		table.foreach(Player.Inventory, function(_, Item)
			if Item.Settings.Damage then
				Item.Settings.Damage = math.huge
			end
		end)
	end)
end

local newPlayerData = GodMode(1337)
```
Nothing is mutated and anything that isn't changed maintains its references. Additionally, the entire structure of newPlayerData is frozen, making it completely immutable.

## Limitations
Unfortunately Luau doesn't support the _pairs_ or _ipairs_ metamethods. This makes it difficult to accurately emulate JavaScript-like proxies. Roblox is, however, considering an _iter_ metamethod. Until it exists, Draft exports an `Iterate` function which can be used to iterate over your current draft. Similarly, the table library doesn't fire _index_ or _newindex_. Draft exports custom functions to emulate the table library. It also exports custom `getmetatable` and `setmetatable` functions.

These can be accessed in two ways. The first is directly from the Draft module.
```lua
local Draft = require(...Draft)
local Produce = Draft.Produce
local Iterate = Draft.Iterate
...
```
The second is through the second argument of Produce, which returns a dictionary.
```lua
Produce(oldState, function(Draft, table)
	table.Iterate(...)
	table.insert(...)
	table.getmetatable(...)
	...
```

Currently, Draft copies on read instead of write, meaning performance is not good. This will be changed in the future. In most cases, this is negligible, but it's worth considering. If you can easily write the same code using something like Llama, do that instead.