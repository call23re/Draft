return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Draft = require(ReplicatedStorage.Draft)
	local Produce = Draft.Produce

	local oldState = {}
	for _ = 1, 10 do
		table.insert(oldState, table.create(10, math.random(0, 1)))
	end

	describe("Inverse", function()

		local newState = Produce(oldState, function(Draft)
			for y = 1, 10 do
				local row = Draft[y]
				for x = 1, 10 do
					row[x] = (row[x] == 1 and 0 or 1)
				end
			end
		end)
	
		local inverted = true
		for y, row in pairs(newState) do
			for x, value in pairs(row) do
				if value == oldState[y][x] then
					inverted = false
					break;
				end
			end
		end

		it("should be inverted", function()
			expect(inverted).to.equal(true)
		end)

	end)

	describe("Malformed Inverse", function()
		local newState = Produce(oldState, function(Draft)
			for y = 1, 10 do
				local row = Draft[y]
				for x = 1, 10 do
					row[x] = (row[x] == 1 and 0 or 1)
				end
			end
			Draft[3][6] = (Draft[3][6] == 1) and 0 or 1
		end)
	
		local inverted = true
		for y, row in pairs(newState) do
			for x, value in pairs(row) do
				if value == oldState[y][x] then
					inverted = false
					break;
				end
			end
		end

		it("shouldn't be inverted", function()
			expect(inverted).to.equal(false)
		end)
	end)
end