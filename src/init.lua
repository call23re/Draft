local PROXY_SYMBOL = newproxy()
local ID = 0

local ProxyLookup = {}
local CloneLookup = {}

local function shallowcopy(orig)
	local copy = {}

	for key, value in pairs(orig) do
		copy[key] = value
	end

	setmetatable(copy, getmetatable(orig))

	return copy
end

local function Propogate(Node, Property, Value)
	Node[Property] = Value
	
	local parent = Node.Parent
	while parent do
		parent[Property] = Value
		parent = parent.Parent
	end
end

local function MakeProxy(Node, Parent, id)
	local Proxy = {
		Node = Node,
		Parent = Parent,
		Type = PROXY_SYMBOL,
		Copy = shallowcopy(Node),
		Modified = false,
		Proxy = newproxy(true), -- has to be a userdata for the __len metamethod to work
		ID = id
	}

	if not Parent then
		ID += 1
		Proxy.ID = ID
	end

	local mt = getmetatable(Proxy.Proxy)

	mt.__index = function(_, index)
		local value = Proxy.Modified and Proxy.Copy[index] or Proxy.Node[index]

		if typeof(value) == "table" then
			if value.Type == PROXY_SYMBOL then
				return value
			end

			-- this is required to deal with certain edge cases regarding cyclic tables
			if CloneLookup[value] then
				return CloneLookup[value].Proxy
			end

			-- if there's not already a proxy for the table, make one
			local newProxy = MakeProxy(value, Proxy, Proxy.ID)
			Proxy.Copy[index] = newProxy.Proxy
			CloneLookup[value] = newProxy
			value = newProxy.Proxy
		end

		return value
	end

	mt.__newindex = function(_, key, value)
		if not Proxy.Modified then
			Propogate(Proxy, "Modified", true)
		end

		Proxy.Copy[key] = value
	end

	-- reroute other metamethods to the original (cloned) table
	-- missing __metatable and __mode
	-- currently not supporting __metatable because it interferes with freezing

	mt.__call = function(_, ...)
		return Proxy.Copy(...)
	end

	mt.__concat = function(a, b)
		if rawequal(a, Proxy.Proxy) then
			return Proxy.Copy .. b
		end
		return b .. Proxy.Copy
	end

	mt.__unm = function()
		return -Proxy.Copy
	end

	mt.__add = function(a, b)
		local value = (rawequal(a, Proxy.Proxy) and b or a)
		return Proxy.Copy + value
	end

	mt.__sub = function(a, b)
		if rawequal(a, Proxy.Proxy) then
			return Proxy.Copy - b
		end
		return a - Proxy.Copy
	end

	mt.__mul = function(a, b)
		local value = (rawequal(a, Proxy.Proxy) and b or a)
		return Proxy.Copy * value
	end

	mt.__div = function(a, b)
		if rawequal(a, Proxy.Proxy) then
			return Proxy.Copy / b
		end
		return a / Proxy.Copy
	end

	mt.__mod = function(a, b)
		if rawequal(a, Proxy.Proxy) then
			return Proxy.Copy % b
		end
		return a % Proxy.Copy
	end

	mt.__pow = function(a, b)
		if rawequal(a, Proxy.Proxy) then
			return Proxy.Copy ^ b
		end
		return a ^ Proxy.Copy
	end

	mt.__tostring = function()
		return tostring(Proxy.Copy)
	end

	mt.__eq = function(a, b)
		local value = (rawequal(a, Proxy.Proxy) and b or a)
		return Proxy.Copy == value
	end

	mt.__lt = function(a, b)
		if rawequal(a, Proxy.Proxy) then
			return a.Copy < b
		end
		return a < b.Copy
	end

	mt.__le = function(a, b)
		if rawequal(a, Proxy.Proxy) then
			return a.Copy <= b
		end
		return a <= b.Copy
	end

	mt.__len = function()
		return #Proxy.Copy
	end

	ProxyLookup[Proxy.Proxy] = Proxy

	return Proxy
end

-- Reconstructs state from a mixed tree of proxies and regular tables.
-- Uses a stack instead of recursion because it's easier (at least in this case) to reason about.
local function ConstructState(Root)
	local Tree = {}
	local currentNode = Tree

	local toVisit = {{Tree, "Root", Root}}
	local visited = {}

	while #toVisit > 0 do

		local nextNode = table.remove(toVisit, 1)
		local root = nextNode[1]
		local key = nextNode[2]
		local node = nextNode[3]

		local isProxy = node.Type and (node.Type == PROXY_SYMBOL)

		local Data;
		if isProxy then
			Data = node.Modified and node.Copy or node.Node
		else
			Data = node
		end

		if not table.isfrozen(root) then
			root[key] = Data
		end

		visited[currentNode] = true
		currentNode = Data

		if not visited[currentNode] then
			for key, value in pairs(Data) do
				if not visited[value] then
					if type(value) == "table" then
						table.insert(toVisit, {currentNode, key, value})
					elseif type(value) == "userdata" then
						if ProxyLookup[value] then
							table.insert(toVisit, {currentNode, key, ProxyLookup[value]})
						end
					end
				end
			end
		end

		if #toVisit == 0 then
			visited[currentNode] = true
		end

	end

	for v, _ in pairs(visited) do
		if not table.isfrozen(v) then
			table.freeze(v)
		end
	end

	return Tree
end

--[=[
	Immer-like module for handling immutable state.
	Especially advantageous when you want to make changes to deeply nested layers of your state.
	Made for Luau. 
	@class Draft
]=]
local Draft = {}

--[=[
	@param State table -- The current state
	@param callback function -- Calls back a mutable proxy table which reflects your current state and a dictionary containing utility functions
	@return table -- The updated state
	@function Produce
	@within Draft
]=]
Draft.Produce = function(State, callback)
	if type(State) ~= "table" then error("Expected table") return end
	if type(callback) ~= "function" then error("Expected function") return end

	local Proxy = MakeProxy(State)

	callback(Proxy.Proxy, Draft)

	local newState = ConstructState(Proxy).Root

	-- Clean up reference tables
	for key, value in pairs(CloneLookup) do
		if value.ID == Proxy.ID then
			CloneLookup[key] = nil
		end
	end

	for key, value in pairs(ProxyLookup) do
		if value.ID == Proxy.ID then
			ProxyLookup[key] = nil
		end
	end

	ID -= 1

	return newState
end

--[=[
	Luau doesn't have pairs or ipairs metamethods, so this replaces some of that functionality.
	@param Proxy userdata -- Reference to your proxy draft
	@param callback function -- Calls back key and value for each item in proxy
	@function Iterate
	@within Draft
]=]
Draft.Iterate = function(Proxy, callback)
	if type(Proxy) ~= "userdata" then error("Provided value is not iterable") end
	if type(callback) ~= "function" then error("Expected function") end

	local metadata = ProxyLookup[Proxy]
	if not metadata then error("Provided value is not iterable") end

	for key, value in pairs(metadata.Copy) do
		if type(value) == "table" then
			if value.Type and value.Type == PROXY_SYMBOL then
				value = value.Proxy
			else
				local newProxy = MakeProxy(value, metadata, metadata.ID)
				Proxy[key] = newProxy.Proxy
				value = newProxy.Proxy
			end
		end

		callback(key, value)
	end
end

--[=[
	Alias for Iterate
	@param Proxy userdata -- Reference to your proxy draft
	@param callback function -- Calls back key and value for each item in proxy
	@function foreach
	@within Draft
]=]
Draft.foreach = Draft.Iterate
--[=[
	Alias for Iterate
	@param Proxy userdata -- Reference to your proxy draft
	@param callback function -- Calls back key and value for each item in proxy
	@function pairs
	@within Draft
]=]
Draft.pairs = Draft.Iterate

Draft.fauxGetmetatable = function(Node)
	return getmetatable(Node.Modified and Node.Copy or Node.Modified)
end

Draft.fauxSetmetatable = function(Node, mt)
	local res = setmetatable(Node.Copy, mt)
	
	Propogate(Node, "Modified", true)
	
	return res
end

-- compatible default table functions

--[=[
	Alias for table.insert
	@param table table
	@param position number -- Optional
	@param value Variant
	@function insert
	@within Draft
]=]
Draft.insert = function(tbl, ...)
	local Node = ProxyLookup[tbl]
	
	if Node then
		table.insert(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return
	end
	
	table.insert(tbl, ...)
end

--[=[
	Alias for table.remove
	@param table table
	@param position number
	@function remove
	@within Draft
]=]
Draft.remove = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		local res = table.remove(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return res
	end

	return table.remove(tbl, ...)
end

--[=[
	Alias for table.clear
	@param table table
	@function clear
	@within Draft
]=]
Draft.clear = function(tbl)
	local Node = ProxyLookup[tbl]

	if Node then
		table.clear(Node.Copy)
		Propogate(Node, "Modified", true)
		return
	end

	table.clear(tbl)
end

--[=[
	Alias for table.concat
	@param table table
	@param separator string
	@param i number -- defaults to 1
	@param j number
	@function concat
	@within Draft
]=]
Draft.concat = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.concat(Node.Copy, ...)
	end

	return table.concat(tbl, ...)
end

--[=[
	Alias for table.create
	@param count number
	@param value Variant
	@function create
	@within Draft
]=]
Draft.create = table.create

--[=[
	Alias for table.find
	@param haystack table
	@param needle Variant
	@param init number
	@function find
	@within Draft
]=]
Draft.find = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.find(Node.Copy, ...)
	end

	return table.find(tbl, ...)
end

--[=[
	Alias for table.freeze
	@param table table
	@function freeze
	@within Draft
]=]
Draft.freeze = function(tbl)
	local Node = ProxyLookup[tbl]
	
	if Node then
		table.freeze(Node.Copy)
		Propogate(Node, "Modified", true)
		return
	end
	
	table.freeze(tbl)
end

--[=[
	Alias for table.isfrozen
	@param table table
	@function isfrozen
	@within Draft
]=]
Draft.isfrozen = function(tbl)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.isfrozen(Node.Copy)
	end

	return table.isfrozen(tbl)
end

--[=[
	Alias for table.getn
	@param table table
	@function getn
	@within Draft
]=]
Draft.getn = function(tbl)
	local Node = ProxyLookup[tbl]
	
	if Node then
		return #Node.Copy
	end
	
	return #tbl
end

--[=[
	Alias for table.move
	@param a1 table
	@param f number
	@param e number
	@param t number
	@param a2 table
	@function move
	@within Draft
]=]
Draft.move = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		table.move(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return
	end

	table.move(tbl, ...)
end

--[=[
	Alias for table.pack
	@param values Variant
	@function pack
	@within Draft
]=]
Draft.pack = table.pack

--[=[
	Alias for table.sort
	@param table table
	@param comparator function -- Optional
	@function sort
	@within Draft
]=]
Draft.sort = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		table.sort(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return
	end

	table.sort(tbl, ...)
end

--[=[
	Alias for table.unpack
	@param table table
	@param i number
	@param j number
	@function unpack
	@within Draft
]=]
Draft.unpack = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.unpack(Node.Copy)
	end

	return table.unpack(tbl)
end

return Draft