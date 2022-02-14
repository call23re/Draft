return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Produce = require(ReplicatedStorage.Draft).Produce

	local oldState = {
		foo = 1,
		bar = {
			a = 2,
			b = {
				c = 3,
				d = 4
			}
		},
		e = {}
	}
	

	describe("Compare", function()

		local newState = Produce(oldState, function(Draft)
			Draft.foo = 2
			
			local b = Draft.bar.b
			
			for key, _ in pairs(b) do
				b[key] *= 2
			end
		end)

		it("should be different", function()
			expect(newState ~= oldState).to.equal(true)
		end)

		it("foo be different", function()
			expect(newState.foo ~= oldState.foo).to.equal(true)
		end)

		it("new foo should become 2", function()
			expect(newState.foo == 2).to.equal(true)
		end)

		it("e should stay the same", function()
			expect(oldState.e == newState.e).to.equal(true)
		end)

	end)
end