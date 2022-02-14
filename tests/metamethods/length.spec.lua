return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Produce = require(ReplicatedStorage.Draft).Produce

	local oldState = table.create(math.random(1, 10000))
	local length = #oldState

	local res;
		
	Produce(oldState, function(Draft)
		res = #Draft
	end)

	it("length should match", function()
		expect(res).to.equal(length)
	end)
end