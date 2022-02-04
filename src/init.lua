local PROXY_SYMBOL = newproxy(true)

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
		Reference = node,
		Parent = parent,
		Type = PROXY_SYMBOL,
		Clone = shallowcopy(node),
		Modified = false
	}

	-- todo: abstract all this to separate Proxy class
	setmetatable(Proxy, {
		__index = function(self, index)
			local value = self.Modified and self.Clone[index] or self.Reference[index]

			if typeof(value) == "table" then
				if value.Type == PROXY_SYMBOL then
					return value
				end
				local newProxy = MakeProxy(value, self)
				self.Clone[index] = newProxy
				value = newProxy
			end

			return value
		end,

		__newindex = function(self, key, value)
			if not self.Modified then
				self.Modified = true

				-- propgate change up tree
				local parent = self.Parent
				while parent do
					parent.Modified = true
					parent = parent.Parent
				end
			end

			self.Clone[key] = value

		end,

		__metatable = function()
			return getmetatable(Proxy.Modified and Proxy.Clone or Proxy.Reference)
		end,

		__call = function(self, ...)
			return self.Clone(...)
		end,

		__concat = function(a, b)
			if rawequal(a, Proxy) then
				return Proxy.Clone .. b
			end
			return b .. Proxy.Clone
		end,

		__unm = function()
			return -Proxy.Clone
		end,

		__add = function(a, b)
			local value = (rawequal(a, Proxy) and b or a)
			return Proxy.Clone + value
		end,

		__sub = function(a, b)
			if rawequal(a, Proxy) then
				return a.Clone - b
			end
			return a - b.Clone
		end,

		__mul = function(a, b)
			local value = (rawequal(a, Proxy) and b or a)
			return Proxy.Clone * value
		end,

		__div = function(a, b)
			if rawequal(a, Proxy) then
				return a.Clone / b
			end
			return a / b.Clone
		end,

		__mod = function(a, b)
			if rawequal(a, Proxy) then
				return a.Clone % b
			end
			return a % b.Clone
		end,

		__pow = function(a, b)
			if rawequal(a, Proxy) then
				return a.Clone ^ b
			end
			return a ^ b.Clone
		end,

		__tostring = function()
			return tostring(Proxy.Clone)
		end,

		__eq = function(a, b)
			local value = (rawequal(a, Proxy) and b or a)
			return Proxy.Clone == value
		end,

		__lt = function(a, b)
			if rawequal(a, Proxy) then
				return a.Clone < b
			end
			return a < b.Clone
		end,

		__le = function(a, b)
			if rawequal(a, Proxy) then
				return a.Clone <= b
			end
			return a <= b.Clone
		end,

		__len = function()
			return #Proxy.Clone
		end
	})

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
			Data = node.Modified and node.Clone or node.Reference
		else
			Data = node
		end
		
		root[key] = Data
		table.insert(visited, currentNode)
		currentNode = Data
		
		for key, value in pairs(Data) do
			if type(value) == "table" then
				table.insert(toVisit, {currentNode, key, value})
			end
		end
		
		if #toVisit == 0 then
			table.insert(visited, currentNode)
		end

	end
	
	for _, v in pairs(visited) do
		table.freeze(v)
	end
	
	return Tree
end

local function Iterate(Node, callback)
	for key, value in pairs(Node.Clone) do
		if type(value) == "table" then
			if value.Type and value.Type == PROXY_SYMBOL then
				value = value.Clone
			else
				local proxy = MakeProxy(value, Node)
				Node[key] = proxy
				value = proxy
			end
		end
		callback(key, value)
	end
end

local function fauxGetmetatable(Node)
	return getmetatable(Node.Modified and Node.Clone or Node.Modified)
end

local function fauxSetmetatable(Node, mt)
	local res = setmetatable(Node.Clone, mt)

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

	callback(Proxy, {
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