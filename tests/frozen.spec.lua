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
		e = {
			f = {
				g = {
					h = {
						i = 5
					}
				}
			}
		}
	}
	

	describe("Frozen", function()

		local newState = Produce(oldState, function(Draft)
			Draft.foo = 2
			Draft.bar.b.c = 4
			Draft.e.f.g.h.i = 6
		end)

		it("newState should be frozen", function()
			expect(table.isfrozen(newState)).to.equal(true)
		end)

		it("deepest layer should be frozen", function()
			expect(table.isfrozen(newState.e.f.g.h)).to.equal(true)
		end)

		-- secondary frozen check
		it("should not be able to write new data", function()
			expect(function()
				newState.newValue = true
			end).to.throw()
		end)

	end)
end