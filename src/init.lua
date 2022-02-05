local Proxy = require(script.Proxy)

local ProxySymbol = newproxy()

local lookup = {}

local function MakeProxy(Node, Parent)

	local metadata = {
		Node = Node,
		Parent = Parent,
		Type = ProxySymbol,
		Modified = false,
		Copy = {}
	}

	metadata.Proxy = Proxy.new(metadata.Copy, {
		Get = function(_, index)
			local res = metadata.Copy[index]
			res = (res ~= nil) and res or Node[index]

			if res ~= nil then
				if type(res) == "table" then
					if not (res.Type and res.Type == ProxySymbol) then
						local newProxy = MakeProxy(res, metadata)
						metadata.Copy[index] = newProxy
						res = newProxy.Proxy
					else
						res = res.Proxy
					end
				end
			end

			return res
		end,

		Set = function(ref, key, value)
			if type(value) == "table" then
				if not (value.Type and value.Type == ProxySymbol) then
					value = MakeProxy(value, metadata)
				end
			end

			metadata.Modified = true
			metadata.Copy[key] = value

			local parent = metadata.Parent
			while parent do
				parent.Modified = true
				parent = parent.Parent
			end
		end,
	})

	lookup[metadata.Proxy] = metadata

	return metadata
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

		local isProxy = node.Type and (node.Type == ProxySymbol)

		local Data;
		if isProxy then
			Data = node.Modified and node.Copy or node.Node
			if node.Modified then
				for key, value in pairs(node.Node) do
					if Data[key] == nil then
						Data[key] = value
					end
				end
			end
		else
			Data = node
		end
		
		if not table.isfrozen(root) then
			root[key] = Data
		end
		
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
		if not table.isfrozen(v) then
			table.freeze(v)
		end
	end

	return Tree.Root
end

local function Iterate(Node, callback)
	local metadata = lookup[Node]
	local seen = {}
	
	for key, value in pairs(metadata.Copy) do
		seen[key] = true

		if type(value) == "table" then
			if value.Type and value.Type == ProxySymbol then
				value = value.Proxy
			else
				local proxy = MakeProxy(value, Node)
				Node[key] = proxy
				value = proxy.Proxy
			end
		end

		callback(key, value)
	end

	for key, value in pairs(metadata.Node) do
		if not seen[key] then
			if type(value) == "table" then
				if value.Type and value.Type == ProxySymbol then
					value = value.Proxy
				else
					local proxy = MakeProxy(value, Node)
					Node[key] = proxy
					value = proxy.Proxy
				end
			end
			callback(key, value)
		end
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

	local metadata = MakeProxy(State)
	callback(metadata.Proxy, {
		Iterate = Iterate,
		Pairs = Iterate,
		setmetatable = fauxSetmetatable,
		getmetatable = fauxGetmetatable
	})

	return ConstructState(metadata)
end

return {
	Produce = Produce,
	Iterate = Iterate,
	Pairs = Iterate,
	setmetatable = fauxSetmetatable,
	getmetatable = fauxGetmetatable
}