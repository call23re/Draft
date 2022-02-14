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

	for v in pairs(visited) do
		if not table.isfrozen(v) then
			table.freeze(v)
		end
	end

	return Tree
end

-- Global wrappers
local function _next(t, lastKey)
	local metadata = ProxyLookup[t]
	if not metadata then
		return next(t, lastKey)
	end

	local key, value = next(metadata.Copy, lastKey)

	if type(key) == "table" then
		if key.Type and key.Type == PROXY_SYMBOL then
			key = key.Proxy
		else
			local newProxy = MakeProxy(key, metadata, metadata.ID)
			t[key] = nil
			t[newProxy.Proxy] = value
			key = newProxy.Proxy
		end
	end

	if type(value) == "table" then
		if value.Type and value.Type == PROXY_SYMBOL then
			value = value.Proxy
		else
			local newProxy = MakeProxy(value, metadata, metadata.ID)
			t[key] = newProxy.Proxy
			value = newProxy.Proxy
		end
	end

	return key, value
end

local function _pairs(Proxy)
	local metadata = ProxyLookup[Proxy]
	if not metadata then
		return next, Proxy, nil
	end
	return _next, Proxy, nil
end

local function iter(t, i)
	i += 1

	local metadata = ProxyLookup[t]
	local value = metadata and metadata.Copy[i] or t[i]

	if metadata then
		if type(value) == "table" then
			if value.Type and value.Type == PROXY_SYMBOL then
				value = value.Proxy
			else
				local newProxy = MakeProxy(value, metadata, metadata.ID)
				t[i] = newProxy.Proxy
				value = newProxy.Proxy
			end
		end
	end

	if value then
		return i, value
	end
end

local function _ipairs(t)
	return iter, t, 0
end

local function _print(...)
	local Values = {...}
	local newValues = {}
	
	for _, Value in pairs(Values) do
		local metadata = ProxyLookup[Value]
		if metadata then
			table.insert(newValues, metadata.Modified and metadata.Copy or metadata.Node)
		else
			table.insert(newValues, Value)
		end
	end
	
	print(unpack(newValues))
end

-- global table wrappers
local Table = {}

Table.foreach = function(tbl, callback)
	for key, value in _pairs(tbl) do
		callback(key, value)
	end
end

Table.insert = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		table.insert(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return
	end

	table.insert(tbl, ...)
end

Table.remove = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		local res = table.remove(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return res
	end

	return table.remove(tbl, ...)
end

Table.clear = function(tbl)
	local Node = ProxyLookup[tbl]

	if Node then
		table.clear(Node.Copy)
		Propogate(Node, "Modified", true)
		return
	end

	table.clear(tbl)
end

Table.concat = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.concat(Node.Copy, ...)
	end

	return table.concat(tbl, ...)
end

Table.create = table.create

Table.find = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.find(Node.Copy, ...)
	end

	return table.find(tbl, ...)
end

Table.freeze = function(tbl)
	local Node = ProxyLookup[tbl]

	if Node then
		table.freeze(Node.Copy)
		Propogate(Node, "Modified", true)
		return
	end

	table.freeze(tbl)
end

Table.isfrozen = function(tbl)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.isfrozen(Node.Copy)
	end

	return table.isfrozen(tbl)
end

Table.getn = function(tbl)
	local Node = ProxyLookup[tbl]

	if Node then
		return #Node.Copy
	end

	return #tbl
end

Table.move = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		table.move(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return
	end

	table.move(tbl, ...)
end

Table.pack = table.pack

Table.sort = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		table.sort(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return
	end

	table.sort(tbl, ...)
end

Table.unpack = function(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.unpack(Node.Copy)
	end

	return table.unpack(tbl)
end

local function _getmetatable(Node)
	local Node = ProxyLookup[Node]

	if Node then
		return getmetatable(Node.Modified and Node.Copy or Node.Node)
	end

	return getmetatable(Node)
end

local function _setmetatable(Node, mt)
	local Node = ProxyLookup[Node]

	if Node then
		local res = setmetatable(Node.Copy, mt)
		Propogate(Node, "Modified", true)
		return res
	end

	return setmetatable(Node, mt)
end

local function Produce(State, callback)
	if type(State) ~= "table" then error("Expected table") return end
	if type(callback) ~= "function" then error("Expected function") return end

	local Proxy = MakeProxy(State)

	setfenv(callback, setmetatable({
		table = Table,
		next = _next,
		pairs = _pairs,
		ipairs = _ipairs,
		print = _print,
		getmetatable = _getmetatable,
		setmetatable = _setmetatable
	}, {__index = getfenv()}))

	callback(Proxy.Proxy)

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

return {
	Produce = Produce
}