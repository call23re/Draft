# Draft
Immer-like module for handling immutable state. Made for Luau. Not currently stable. Needs lots of refactoring and testing. :(

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

local newState = Produce(oldState, function(Draft, Util)
	Draft.foo = 2
	
	local b = Draft.bar.b
	
	Util.Iterate(b, function(key, value)
		b[key] *= 2
	end)
end)
```
Inverting a 2d array:
```lua
local Produce = require(...Draft).Produce

local oldState = {}
for y = 1, 10 do
	table.insert(oldState, table.create(10, math.random(0, 1)))
end

local newState = Produce(oldState, function(Draft, Util)
	Util.Iterate(Draft, function(y, row)
		Util.Iterate(row, function(x, value)
			row[x] = (value == 1 and 0 or 1)
		end)
	end)
end)
```

## Limitations
Unfortunately Luau doesn't support the _pairs_ or _ipairs_ metamethods. This makes it difficult to accurately emulate JavaScript-like proxies. Roblox is, however, considering an _iter_ metamethod. Until it exists, Draft exports an `Iterate` function which can be used to iterate over your current draft. It also exports custom `getmetamethod` and `setmetamethod` functions.

These can be accessesd in two ways. The first is directly from the Draft module.
```lua
local Draft = require(...Draft)
local Produce = Draft.Produce
local Iterate = Draft.Iterate
...
```
The second is through the second argument of Produce, which returns a dictionary.
```lua
Produce(oldState, function(Draft, Util)
	Util.Iterate(...)
	Util.getmetatable(...)
	...
```