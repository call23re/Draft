return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Draft = require(ReplicatedStorage.Draft)
	local Produce = Draft.Produce

	local Items = {
		Cool_Gun = {
			ID = 1,
			Name = "Cool Gun 😎",
			Settings = {
				Damage = 60,
				Dropoff = 100,
				FireRate = 10,
				Magazine = 30
			}
		},
		Epic_Sword = {
			ID = 2,
			Name = "EPIC SWORD :O",
			Settings = {
				Damage = 60
			}
		},
		Lame_Flashlight = {
			ID = 3,
			Name = "flashlight...",
			Settings = {
				Brightness = 0.1,
				Distance = 10
			}
		}
	}
	
	local PlayerData = {
		[1337] = {
			Username = "cornprices",
			Health = 100,
			Stats = {
				Level = 100,
				Points = 100000
			},
			Inventory = {
				Items.Cool_Gun,
				Items.Lame_Flashlight
			}
		},
		[7331] = {
			Username = "call23re2",
			Health = 100,
			Stats = {
				Level = 10,
				Points = 1000
			},
			Inventory = {
				Items.Epic_Sword,
				Items.Lame_Flashlight
			}
		}
	}

	describe("God Mode", function()
		local function GodMode(ID)
			return Produce(PlayerData, function(Draft, table)
				local Player = Draft[ID]
				
				Player.Health = math.huge
				Player.Stats.Level = math.huge
				Player.Stats.Points = math.huge
				
				table.foreach(Player.Inventory, function(_, Item)
					if Item.Settings.Damage then
						Item.Settings.Damage = math.huge
					end
				end)
			end)
		end
		
		local newPlayerData = GodMode(1337)

		local testPlayer = newPlayerData[1337]
		local otherPlayer = newPlayerData[7331]

		it("Data should be updated", function()
			expect(testPlayer.Health).to.equal(math.huge)
			expect(testPlayer.Stats.Level).to.equal(math.huge)
			expect(testPlayer.Stats.Points).to.equal(math.huge)
		end)

		it("Items should be updated", function()
			for _, Item in pairs(testPlayer.Inventory) do
				if Item.Settings.Damage then
					expect(Item.Settings.Damage).to.equal(math.huge)
				end
			end
		end)

		it("Other player reference should be the same", function()
			expect(otherPlayer).to.equal(PlayerData[7331])
		end)
	end)

end