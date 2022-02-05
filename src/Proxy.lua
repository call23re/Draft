-- Metatable wrapper

local Proxy = {}
Proxy.__index = Proxy

function Proxy.new(Target, Handler)
	if type(Target) ~= "table" then error("Expected table") end
	if type(Handler) ~= "table" then error("Expected table") end

	local self = setmetatable({}, Proxy)

	setmetatable(self, {
		__index = function(_, index)
			local res = Handler.Get and Handler.Get(Target, index) or Target[index]
			return res
		end,

		__newindex = function(_, key, value)
			if Handler.Set then
				Handler.Set(Target, key, value)
			else
				Target[key] = value
			end
		end
	})

	return self
end

return Proxy