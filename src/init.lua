local PROXY_SYMBOL = newproxy()

local lookup = {}

local function shallowcopy(orig)
	local copy = {}

	for key, value in pairs(orig) do
		copy[key] = value
	end

	setmetatable(copy, getmetatable(orig))

	return copy
end

local function MakeProxy(node, parent)
	local Proxy = {
		Node = node,
		Parent = parent,
		Type = PROXY_SYMBOL,
		Copy = shallowcopy(node),
		Modified = false,
		Proxy = newproxy(true)
	}

	-- TODO: abstract all this to separate Proxy class
	local mt = getmetatable(Proxy.Proxy)

	local custom = {
		__index = function(_, index)
			local value = Proxy.Modified and Proxy.Copy[index] or Proxy.Node[index]

			if typeof(value) == "table" then
				if value.Type == PROXY_SYMBOL then
					return value
				end
				local newProxy = MakeProxy(value, Proxy)
				Proxy.Copy[index] = newProxy.Proxy
				value = newProxy.Proxy
			end

			return value
		end,

		__newindex = function(_, key, value)
			if not Proxy.Modified then
				rawset(Proxy, "Modified", true)

				-- propgate change up tree
				local parent = Proxy.Parent
				while parent do
					rawset(parent, "Modified", true)
					parent = parent.Parent
				end
			end

			Proxy.Copy[key] = value

		end,

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

	lookup[Proxy.Proxy] = Proxy

	for key, value in pairs(custom) do
		mt[key] = value
	end

	return Proxy
end

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

		root[key] = Data
		table.insert(visited, currentNode)
		currentNode = Data

		for key, value in pairs(Data) do
			if type(value) == "table" then
				table.insert(toVisit, {currentNode, key, value})
			elseif type(value) == "userdata" then
				if lookup[value] then
					table.insert(toVisit, {currentNode, key, lookup[value]})
				end
			end
		end

		if #toVisit == 0 then
			table.insert(visited, currentNode)
		end

	end

	for _, v in pairs(visited) do
		if not table.isfrozen(v) then
			table.freeze(v)
		end
	end

	return Tree
end

local function Iterate(Node, callback)
	if type(Node) ~= "userdata" then error("Provided value is not iterable") end
	if type(callback) ~= "function" then error("Expected function") end
	
	local metadata = lookup[Node]
	if not metadata then error("Provided value is not iterable") end
	
	for key, value in pairs(metadata.Copy) do
		if type(value) == "table" then
			if value.Type and value.Type == PROXY_SYMBOL then
				value = value.Proxy
			else
				local proxy = MakeProxy(value, metadata)
				Node[key] = proxy.Proxy
				value = proxy.Proxy
			end
		end

		callback(key, value)
	end
end

local function fauxGetmetatable(Node)
	return getmetatable(Node.Modified and Node.Copy or Node.Modified)
end

local function fauxSetmetatable(Node, mt)
	local res = setmetatable(Node.Copy, mt)

	Node.Modified = true

	-- propgate change up tree
	local parent = Node.Parent
	while parent do
		parent.Modified = true
		parent = parent.Parent
	end

	return res
end

local function Produce(State, callback)
	if type(State) ~= "table" then error("Expected table") return end
	if type(callback) ~= "function" then error("Expected function") return end

	local Proxy = MakeProxy(State)

	callback(Proxy.Proxy, {
		Iterate = Iterate,
		Pairs = Iterate,
		setmetatable = fauxSetmetatable,
		getmetatable = fauxGetmetatable
	})

	return ConstructState(Proxy).Root
end

return {
	Produce = Produce,
	Iterate = Iterate,
	setmetatable = fauxSetmetatable,
	getmetatable = fauxGetmetatable
}