return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Draft = require(ReplicatedStorage.Draft)
	local Produce = Draft.Produce

	local oldState = {
		value = 5
	}
	setmetatable(oldState, {
		__add = function(a, b)
			local value = (type(a) == "table" and b or a)
			return value + oldState.value
		end
	})
	

	describe("Compare", function()

		local res;

		Produce(oldState, function(Draft, Util)
			Draft.w = 1
			res = Draft + 6
		end)

		it("should be 11", function()
			expect(res).to.equal(11)
		end)

	end)
end