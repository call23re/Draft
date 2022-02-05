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

local function MakeProxy(node, parent, id)
	local Proxy = {
		Node = node,
		Parent = parent,
		Type = PROXY_SYMBOL,
		Copy = shallowcopy(node),
		Modified = false,
		Proxy = newproxy(true), -- has to be a userdata for the __len metamethod to work
		ID = id
	}

	if not parent then
		ID += 1
		Proxy.ID = ID
	end

	-- TODO: abstract all this to separate Proxy class

	local mt = getmetatable(Proxy.Proxy)

	local metamethods = {
		__index = function(_, index)
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
		end,

		__newindex = function(_, key, value)
			if not Proxy.Modified then
				Proxy.Modified = true

				-- propgate change up tree
				local parent = Proxy.Parent
				while parent do
					parent.Modified = true
					parent = parent.Parent
				end
			end

			Proxy.Copy[key] = value

		end,

		-- reroute other metamethods to the original (cloned) table
		-- missing __metatable and __mode
		-- currently not supporting __metatable because it interferes with freezing

		__call = function(_, ...)
			return Proxy.Copy(...)
		end,

		__concat = function(a, b)
			if rawequal(a, Proxy.Proxy) then
				return Proxy.Copy .. b
			end
			return b .. Proxy.Copy
		end,

		__unm = function()
			return -Proxy.Copy
		end,

		__add = function(a, b)
			local value = (rawequal(a, Proxy.Proxy) and b or a)
			return Proxy.Copy + value
		end,

		__sub = function(a, b)
			if rawequal(a, Proxy.Proxy) then
				return Proxy.Copy - b
			end
			return a - Proxy.Copy
		end,

		__mul = function(a, b)
			local value = (rawequal(a, Proxy.Proxy) and b or a)
			return Proxy.Copy * value
		end,

		__div = function(a, b)
			if rawequal(a, Proxy.Proxy) then
				return Proxy.Copy / b
			end
			return a / Proxy.Copy
		end,

		__mod = function(a, b)
			if rawequal(a, Proxy.Proxy) then
				return Proxy.Copy % b
			end
			return a % Proxy.Copy
		end,

		__pow = function(a, b)
			if rawequal(a, Proxy.Proxy) then
				return Proxy.Copy ^ b
			end
			return a ^ Proxy.Copy
		end,

		__tostring = function()
			return tostring(Proxy.Copy)
		end,

		__eq = function(a, b)
			local value = (rawequal(a, Proxy.Proxy) and b or a)
			return Proxy.Copy == value
		end,

		__lt = function(a, b)
			if rawequal(a, Proxy.Proxy) then
				return a.Copy < b
			end
			return a < b.Copy
		end,

		__le = function(a, b)
			if rawequal(a, Proxy.Proxy) then
				return a.Copy <= b
			end
			return a <= b.Copy
		end,

		__len = function()
			return #Proxy.Copy
		end
	}

	ProxyLookup[Proxy.Proxy] = Proxy

	for key, value in pairs(metamethods) do
		mt[key] = value
	end

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

-- Luau doesn't have __pairs or __ipairs, so this replaces some of that functionality.
local function Iterate(Node, callback)
	if type(Node) ~= "userdata" then error("Provided value is not iterable") end
	if type(callback) ~= "function" then error("Expected function") end

	local metadata = ProxyLookup[Node]
	if not metadata then error("Provided value is not iterable") end

	for key, value in pairs(metadata.Copy) do
		if type(value) == "table" then
			if value.Type and value.Type == PROXY_SYMBOL then
				value = value.Proxy
			else
				local proxy = MakeProxy(value, metadata, metadata.ID)
				Node[key] = proxy.Proxy
				value = proxy.Proxy
			end
		end

		callback(key, value)
	end
end

local function Propogate(Node, Property, Value)
	Node[Property] = Value
	
	local parent = Node.Parent
	while parent do
		parent[Property] = Value
		parent = parent.Parent
	end
end

local function fauxGetmetatable(Node)
	return getmetatable(Node.Modified and Node.Copy or Node.Modified)
end

local function fauxSetmetatable(Node, mt)
	local res = setmetatable(Node.Copy, mt)
	
	Propogate(Node, "Modified", true)
	
	return res
end

-- compatible default table functions

local function insert(tbl, ...)
	local Node = ProxyLookup[tbl]
	
	if Node then
		table.insert(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return
	end
	
	table.insert(tbl, ...)
end

local function remove(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		local res = table.remove(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return res
	end

	return table.remove(tbl, ...)
end

local function clear(tbl)
	local Node = ProxyLookup[tbl]

	if Node then
		table.clear(Node.Copy)
		Propogate(Node, "Modified", true)
		return
	end

	table.clear(tbl)
end

local function concat(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.concat(Node.Copy, ...)
	end

	return table.concat(tbl, ...)
end

local function find(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.find(Node.Copy, ...)
	end

	return table.find(tbl, ...)
end

local function freeze(tbl)
	local Node = ProxyLookup[tbl]
	
	if Node then
		table.freeze(Node.Copy)
		Propogate(Node, "Modified", true)
		return
	end
	
	table.freeze(tbl)
end

local function isfrozen(tbl)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.isfrozen(Node.Copy)
	end

	return table.isfrozen(tbl)
end

local function getn(tbl)
	local Node = ProxyLookup[tbl]
	
	if Node then
		return #Node.Copy
	end
	
	return #tbl
end

local function move(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		table.move(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return
	end

	table.move(tbl, ...)
end

local function sort(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		table.sort(Node.Copy, ...)
		Propogate(Node, "Modified", true)
		return
	end

	table.sort(tbl, ...)
end

local function _unpack(tbl, ...)
	local Node = ProxyLookup[tbl]

	if Node then
		return table.unpack(Node.Copy)
	end

	return table.unpack(tbl)
end


-- Takes in a state (table), sends back a "Draft" (proxy), returns a new state
local function Produce(State, callback)
	if type(State) ~= "table" then error("Expected table") return end
	if type(callback) ~= "function" then error("Expected function") return end

	local Proxy = MakeProxy(State)

	callback(Proxy.Proxy, {
		Iterate = Iterate,
		Pairs = Iterate,
		foreach = Iterate,
		
		setmetatable = fauxSetmetatable,
		getmetatable = fauxGetmetatable,
		
		insert = insert,
		remove = remove,
		clear = clear,
		concat = concat,
		find = find,
		freeze = freeze,
		isfrozen = isfrozen,
		getn = getn,
		move = move,
		sort = sort,
		unpack = _unpack
	})

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
	Produce = Produce,
	
	Iterate = Iterate,
	Pairs = Iterate,
	foreach = Iterate,

	setmetatable = fauxSetmetatable,
	getmetatable = fauxGetmetatable,

	insert = insert,
	remove = remove,
	clear = clear,
	concat = concat,
	find = find,
	freeze = freeze,
	isfrozen = isfrozen,
	getn = getn,
	move = move,
	sort = sort,
	unpack = _unpack
}