return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Produce = require(ReplicatedStorage.Draft).Produce

	local oldState = {
		value = 5
	}
	
	setmetatable(oldState, {
		__unm = function()
			return -oldState.value
		end,
		__add = function(a, b)
			local value = (type(a) == "table" and b or a)
			return value + oldState.value
		end,
		__sub = function(a, b)
			local value = (type(a) == "table" and b or a)
			return oldState.value - value
		end,
		__div = function(a, b)
			local value = (type(a) == "table" and b or a)
			return oldState.value / value
		end,
		__mod = function(a, b)
			local value = (type(a) == "table" and b or a)
			return oldState.value % value
		end,
		__pow = function(a, b)
			local value = (type(a) == "table" and b or a)
			return oldState.value ^ value
		end
	})
	
	describe("Unary", function()
	
		local res;
		
		Produce(oldState, function(Draft)
			res = -Draft
		end)

		it("should be -5", function()
			expect(res).to.equal(-5)
		end)

	end)

	describe("Addition", function()

		local res;
		
		Produce(oldState, function(Draft)
			res = Draft + 6
		end)

		it("should be 11", function()
			expect(res).to.equal(11)
		end)

	end)

	describe("Subtraction", function()

		local res;
		
		Produce(oldState, function(Draft)
			res = Draft - 3
		end)

		it("should be 2", function()
			expect(res).to.equal(2)
		end)

	end)

	describe("Division", function()

		local res;
		
		Produce(oldState, function(Draft)
			res = Draft / 2
		end)

		it("should be 2.5", function()
			expect(res).to.equal(2.5)
		end)

	end)

	describe("Modulus", function()

		local res;
		
		Produce(oldState, function(Draft)
			res = Draft % 2
		end)

		it("should be 1", function()
			expect(res).to.equal(1)
		end)

	end)

	describe("Exponent", function()

		local res;
		
		Produce(oldState, function(Draft)
			res = Draft ^ 2
		end)

		it("should be 25", function()
			expect(res).to.equal(25)
		end)

	end)
end