# Draft
Immer-like module for handling immutable state. Made for Luau. Stable but not production ready. Needs lots of refactoring and testing. :(

## Introduction
Like Immer, handling immutable state is simplified to a single `Produce` function. `Produce` takes your previous state and provides a table. This table acts as a proxy of your previous state, meaning changes made to this table won't influence your previous state.

This means that you don't have to deal with copying tables and you aren't constrained to using special immutable data structures or helper functions.

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
	
	table.Iterate(b, function(key, value)
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