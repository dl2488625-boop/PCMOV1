local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Networking
pcall(function()
	Networking = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))
end)

local TargetUsername = "Username"
local Note = "Item Dupe give for you"
local DefaultStackCount = 1
local DefaultSingleCount = 1

local PlantItems = {
	"Hypno Bloom","Mega","Rainbow","Gold","Acorn", "Apple", "Bamboo", "Banana", "Blueberry", "Cactus", "Carrot", "Cherry", "Coconut",
	"Corn", "Dragon fruit", "Dragon's Breath", "Grape", "Green bean", "Mango", "Moon Bloom", "Mushroom",
	"Pineapple", "Poison apple", "Pomegranate", "Strawberry", "Sunflower", "Tomato", "Tulip", "Venus fly trap", "Venom Spitter"
}

local PetItems = {
	"Bee", "BlackDragon", "Bunny", "Deer", "Dragonfly", "Frog", "GoldenDragonfly",
	"IceSerpent", "Monkey", "Owl", "Raccoon", "Robin", "Unicorn", "Turtle", "Eagle", "Deer", "Bear"
}

local GearItems = {
	"Basic Pot", "Common Sprinkler", "Common Watering Can", "Flashbang", "Gnome",
	"Invisibility Mushroom", "Jump Mushroom", "Lantern", "Legendary Sprinkler", "Padding", "Rare Sprinkler",
	"Shrink Mushroom", "Sign", "Speed Mushroom", "Super Sprinkler", "Super Watering Can", "Supersize Mushroom",
	"Teleporter", "Trowel", "Uncommon Sprinkler", "Wheelbarrow"
}

local EggItems = {
	"Common Egg","Rainbow Egg"
}

local GearCategoryByName = {
	["Basic Pot"] = "EmptyPots",
	["Common Sprinkler"] = "Sprinklers",
	["Rare Sprinkler"] = "Sprinklers",
	["Legendary Sprinkler"] = "Sprinklers",
	["Super Sprinkler"] = "Sprinklers",
	["Uncommon Sprinkler"] = "Sprinklers",
	["Common Watering Can"] = "WateringCans",
	["Super Watering Can"] = "WateringCans",
	["Invisibility Mushroom"] = "Mushrooms",
	["Jump Mushroom"] = "Mushrooms",
	["Shrink Mushroom"] = "Mushrooms",
	["Speed Mushroom"] = "Mushrooms",
	["Supersize Mushroom"] = "Mushrooms",
	["Gnome"] = "Gnomes",
	["Trowel"] = "Trowels"
}

local Definitions = {}
local DefinitionByLookup = {}
local DefinitionByCompact = {}

local function normalize(value)
	value = tostring(value or "")
	value = value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return value:lower()
end

local function compact(value)
	return normalize(value):gsub("[^%w]", "")
end

local function addDefinition(kind, itemName, defaultCount)
	local definition = {
		Kind = kind,
		Name = itemName,
		DefaultCount = defaultCount,
		Lookup = normalize(kind .. " " .. itemName)
	}
	table.insert(Definitions, definition)
	DefinitionByLookup[kind .. "\0" .. normalize(itemName)] = definition
	DefinitionByCompact[kind .. "\0" .. compact(itemName)] = definition
end

for _, itemName in ipairs(PlantItems) do
	addDefinition("Plant", itemName, DefaultStackCount)
end
for _, itemName in ipairs(PetItems) do
	addDefinition("Pet", itemName, DefaultSingleCount)
end
for _, itemName in ipairs(GearItems) do
	addDefinition("Gear", itemName, DefaultStackCount)
end
for _, itemName in ipairs(EggItems) do
	addDefinition("Egg", itemName, DefaultStackCount)
end

if _G.MailboxLeftUI then
	for _, connection in ipairs(_G.MailboxLeftUI.Connections or {}) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	if _G.MailboxLeftUI.Gui then
		pcall(function()
			_G.MailboxLeftUI.Gui:Destroy()
		end)
	end
end

local State = {
	Connections = {},
	Rows = {},
	History = {},
	Selected = {},
	Counts = {},
	CountBoxes = {},
	VisibleRows = 0
}
_G.MailboxLeftUI = State

for _, definition in ipairs(Definitions) do
	State.Selected[definition] = false
	State.Counts[definition] = definition.DefaultCount
end

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(State.Connections, connection)
	return connection
end

local function create(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function trim(value)
	return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function definitionKey(kind, itemName)
	return kind .. "\0" .. normalize(itemName)
end

local function getDefinition(kind, itemName)
	return DefinitionByLookup[definitionKey(kind, itemName)] or DefinitionByCompact[kind .. "\0" .. compact(itemName)]
end

local function getCount(definition)
	local box = State.CountBoxes[definition]
	local count = tonumber(box and box.Text) or State.Counts[definition] or definition.DefaultCount
	count = math.max(0, math.floor(count))
	State.Counts[definition] = count
	if box and box.Text ~= tostring(count) then
		box.Text = tostring(count)
	end
	return count
end

local function setStatus(text, color)
	if State.StatusLabel then
		State.StatusLabel.Text = text
		State.StatusLabel.TextColor3 = color or Color3.fromRGB(220, 226, 220)
	end
end

local function summarizeBatch(batch)
	local grouped = {}
	for _, item in ipairs(batch) do
		local name = item.DisplayName or item.ItemKey
		local key = tostring(item.Category) .. "\0" .. tostring(name)
		if not grouped[key] then
			grouped[key] = {
				Name = name,
				Category = item.Category,
				Count = 0
			}
		end
		grouped[key].Count = grouped[key].Count + (tonumber(item.Count) or 0)
	end

	local parts = {}
	for _, item in pairs(grouped) do
		table.insert(parts, string.format("%s:%s x%d", tostring(item.Category), tostring(item.Name), item.Count))
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function stripPrivateFields(batch)
	local clean = {}
	for _, item in ipairs(batch) do
		table.insert(clean, {
			Category = item.Category,
			ItemKey = item.ItemKey,
			Count = item.Count
		})
	end
	return clean
end

local Gui = create("ScreenGui", {
	Name = "MailboxLeftUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, PlayerGui)
State.Gui = Gui

local Main = create("Frame", {
	Name = "Main",
	Position = UDim2.new(0, 10, 0, 70),
	Size = UDim2.new(0, 360, 0, 620),
	BackgroundColor3 = Color3.fromRGB(22, 24, 27),
	BorderSizePixel = 0
}, Gui)
create("UICorner", { CornerRadius = UDim.new(0, 8) }, Main)
create("UIStroke", { Color = Color3.fromRGB(76, 87, 104), Thickness = 1, Transparency = 0.15 }, Main)

local Header = create("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundColor3 = Color3.fromRGB(35, 41, 48),
	BorderSizePixel = 0
}, Main)
create("UICorner", { CornerRadius = UDim.new(0, 8) }, Header)

create("TextLabel", {
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(1, -54, 1, 0),
	BackgroundTransparency = 1,
	Text = "Mailbox Sender",
	TextColor3 = Color3.fromRGB(240, 244, 248),
	TextSize = 17,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left
}, Header)

local CloseButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.new(0, 30, 0, 24),
	BackgroundColor3 = Color3.fromRGB(58, 66, 76),
	Text = "X",
	TextColor3 = Color3.fromRGB(240, 244, 248),
	TextSize = 13,
	Font = Enum.Font.GothamBold
}, Header)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, CloseButton)

local TargetBox = create("TextBox", {
	Position = UDim2.new(0, 12, 0, 48),
	Size = UDim2.new(1, -24, 0, 30),
	BackgroundColor3 = Color3.fromRGB(34, 38, 43),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Text = TargetUsername,
	PlaceholderText = "Target username",
	TextColor3 = Color3.fromRGB(245, 247, 250),
	PlaceholderColor3 = Color3.fromRGB(145, 153, 163),
	TextSize = 14,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left
}, Main)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, TargetBox)
create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, TargetBox)

local NoteBox = create("TextBox", {
	Position = UDim2.new(0, 12, 0, 84),
	Size = UDim2.new(1, -24, 0, 30),
	BackgroundColor3 = Color3.fromRGB(34, 38, 43),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Text = Note,
	PlaceholderText = "Note",
	TextColor3 = Color3.fromRGB(245, 247, 250),
	PlaceholderColor3 = Color3.fromRGB(145, 153, 163),
	TextSize = 14,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left
}, Main)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, NoteBox)
create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, NoteBox)

local SendButton = create("TextButton", {
	Position = UDim2.new(0, 12, 0, 122),
	Size = UDim2.new(1, -24, 0, 34),
	BackgroundColor3 = Color3.fromRGB(42, 116, 76),
	BorderSizePixel = 0,
	Text = "Send Selected Items",
	TextColor3 = Color3.fromRGB(245, 250, 247),
	TextSize = 15,
	Font = Enum.Font.GothamBold
}, Main)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, SendButton)

local SelectVisibleButton = create("TextButton", {
	Position = UDim2.new(0, 12, 0, 164),
	Size = UDim2.new(0.5, -16, 0, 28),
	BackgroundColor3 = Color3.fromRGB(47, 58, 70),
	BorderSizePixel = 0,
	Text = "Select Found",
	TextColor3 = Color3.fromRGB(238, 242, 246),
	TextSize = 12,
	Font = Enum.Font.GothamBold
}, Main)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, SelectVisibleButton)

local ClearButton = create("TextButton", {
	Position = UDim2.new(0.5, 4, 0, 164),
	Size = UDim2.new(0.5, -16, 0, 28),
	BackgroundColor3 = Color3.fromRGB(69, 47, 50),
	BorderSizePixel = 0,
	Text = "Clear",
	TextColor3 = Color3.fromRGB(238, 242, 246),
	TextSize = 12,
	Font = Enum.Font.GothamBold
}, Main)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, ClearButton)

local SearchBox = create("TextBox", {
	Position = UDim2.new(0, 12, 0, 200),
	Size = UDim2.new(1, -24, 0, 30),
	BackgroundColor3 = Color3.fromRGB(34, 38, 43),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Text = "",
	PlaceholderText = "Search item, pet, gear...",
	TextColor3 = Color3.fromRGB(245, 247, 250),
	PlaceholderColor3 = Color3.fromRGB(145, 153, 163),
	TextSize = 14,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left
}, Main)
State.SearchBox = SearchBox
create("UICorner", { CornerRadius = UDim.new(0, 6) }, SearchBox)
create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, SearchBox)

local StatusLabel = create("TextLabel", {
	Position = UDim2.new(0, 12, 0, 236),
	Size = UDim2.new(1, -24, 0, 20),
	BackgroundTransparency = 1,
	Text = "Ready",
	TextColor3 = Color3.fromRGB(220, 226, 220),
	TextSize = 12,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd
}, Main)
State.StatusLabel = StatusLabel

local ItemList = create("ScrollingFrame", {
	Position = UDim2.new(0, 12, 0, 262),
	Size = UDim2.new(1, -24, 0, 242),
	BackgroundColor3 = Color3.fromRGB(18, 20, 23),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y
}, Main)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, ItemList)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6)
}, ItemList)
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 5)
}, ItemList)

create("TextLabel", {
	Position = UDim2.new(0, 12, 0, 512),
	Size = UDim2.new(1, -24, 0, 18),
	BackgroundTransparency = 1,
	Text = "History",
	TextColor3 = Color3.fromRGB(235, 239, 243),
	TextSize = 13,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left
}, Main)

local HistoryList = create("ScrollingFrame", {
	Position = UDim2.new(0, 12, 0, 534),
	Size = UDim2.new(1, -24, 0, 74),
	BackgroundColor3 = Color3.fromRGB(18, 20, 23),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y
}, Main)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, HistoryList)
create("UIPadding", {
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6)
}, HistoryList)
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 5)
}, HistoryList)

local function kindLabel(kind)
	if kind == "Plant" then
		return "Seed/Fruit"
	elseif kind == "Egg" then
		return "Egg"
	end
	return kind
end

local function updateRowText(definition)
	local rowInfo = State.Rows[definition]
	if not rowInfo then
		return
	end

	local selected = State.Selected[definition]
	rowInfo.Toggle.Text = string.format("%s [%s] %s", selected and "[x]" or "[ ]", kindLabel(definition.Kind), definition.Name)
	rowInfo.Toggle.TextColor3 = selected and Color3.fromRGB(235, 239, 243) or Color3.fromRGB(150, 156, 164)
end

local function updateSearch()
	local query = normalize(SearchBox.Text)
	local visible = 0

	for _, definition in ipairs(Definitions) do
		local rowInfo = State.Rows[definition]
		if rowInfo then
			local shown = query == "" or rowInfo.SearchText:find(query, 1, true) ~= nil
			rowInfo.Frame.Visible = shown
			if shown then
				visible = visible + 1
			end
		end
	end

	State.VisibleRows = visible
	setStatus(string.format("Showing %d/%d | Selected %d", visible, #Definitions, State.SelectedCount or 0), Color3.fromRGB(220, 226, 220))
end

local function refreshSelectedCount()
	local selected = 0
	for _, definition in ipairs(Definitions) do
		if State.Selected[definition] then
			selected = selected + 1
		end
	end
	State.SelectedCount = selected
	updateSearch()
end

local function makeItemRow(definition, order)
	local row = create("Frame", {
		Size = UDim2.new(1, -2, 0, 30),
		BackgroundColor3 = order % 2 == 0 and Color3.fromRGB(27, 30, 34) or Color3.fromRGB(31, 35, 40),
		BorderSizePixel = 0,
		LayoutOrder = order
	}, ItemList)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, row)

	local toggle = create("TextButton", {
		Position = UDim2.new(0, 6, 0, 5),
		Size = UDim2.new(1, -96, 0, 20),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(150, 156, 164),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd
	}, row)

	local countBox = create("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.new(0, 80, 0, 21),
		BackgroundColor3 = Color3.fromRGB(42, 47, 54),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Text = tostring(definition.DefaultCount),
		TextColor3 = Color3.fromRGB(245, 247, 250),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Center
	}, row)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, countBox)

	State.CountBoxes[definition] = countBox
	State.Rows[definition] = {
		Frame = row,
		Toggle = toggle,
		SearchText = normalize(definition.Kind .. " " .. kindLabel(definition.Kind) .. " " .. definition.Name)
	}

	connect(toggle.Activated, function()
		State.Selected[definition] = not State.Selected[definition]
		getCount(definition)
		updateRowText(definition)
		refreshSelectedCount()
	end)

	connect(countBox.FocusLost, function()
		getCount(definition)
	end)

	updateRowText(definition)
end

for index, definition in ipairs(Definitions) do
	makeItemRow(definition, index)
end

local function addHistory(status, targetName, batch, detail)
	local timeText = os.date("%Y-%m-%d %H:%M:%S")
	local summary = summarizeBatch(batch)
	if summary == "" then
		summary = "No items"
	end

	local entry = {
		Time = timeText,
		Status = status,
		Target = targetName,
		Items = summary,
		Detail = detail or ""
	}
	table.insert(State.History, 1, entry)

	local line = string.format("[%s] %s -> %s | %s", entry.Time, entry.Status, entry.Target, entry.Items)
	if entry.Detail ~= "" then
		line = line .. " | " .. entry.Detail
	end
	print("[MailboxHistory] " .. line)

	local row = create("TextLabel", {
		Size = UDim2.new(1, -2, 0, 48),
		BackgroundColor3 = status == "Sent" and Color3.fromRGB(27, 45, 35) or Color3.fromRGB(54, 35, 35),
		BorderSizePixel = 0,
		Text = line,
		TextColor3 = Color3.fromRGB(235, 239, 243),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		LayoutOrder = -#State.History
	}, HistoryList)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, row)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 5)
	}, row)

	local rows = {}
	for _, child in ipairs(HistoryList:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(rows, child)
		end
	end
	if #rows > 25 then
		table.sort(rows, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for index = 26, #rows do
			rows[index]:Destroy()
		end
	end
end

local function addBatchItem(batch, category, itemKey, count, displayName)
	if not category or not itemKey or not count or count <= 0 then
		return
	end

	local lookupKey = category .. "\0" .. tostring(itemKey)
	for _, item in ipairs(batch) do
		if item._LookupKey == lookupKey then
			item.Count = item.Count + count
			return
		end
	end

	table.insert(batch, {
		Category = category,
		ItemKey = itemKey,
		Count = count,
		DisplayName = displayName or itemKey,
		_LookupKey = lookupKey
	})
end

local function parseNameBeforeBracket(itemName)
	local parsed = tostring(itemName):match("^(.-)%s*%[")
	if parsed and parsed ~= "" then
		return parsed
	end
	return itemName
end

local function getPlantDefinition(item)
	local seedName = item:GetAttribute("SeedTool")
	if seedName then
		return getDefinition("Plant", seedName), "Seeds", seedName, tonumber(item:GetAttribute("Count")) or 1, seedName
	end

	local fruitName = item:GetAttribute("FruitName") or item:GetAttribute("Fruit")
	if not fruitName and (item:GetAttribute("HarvestedFruit") or item:GetAttribute("FruitProxy")) then
		fruitName = parseNameBeforeBracket(item.Name)
	end

	if fruitName then
		local itemKey = item:GetAttribute("Id") or item.Name
		return getDefinition("Plant", fruitName), "HarvestedFruits", itemKey, 1, fruitName
	end

	return nil
end

local function getPetName(item)
	local petName = item:GetAttribute("PetName") or item:GetAttribute("PetType") or item:GetAttribute("Species")
	local petAttribute = item:GetAttribute("Pet")
	if type(petAttribute) == "string" and petAttribute ~= "" and normalize(petAttribute) ~= "true" then
		petName = petAttribute
	end
	if not petName then
		petName = parseNameBeforeBracket(item.Name)
	end
	return petName
end

local function getPetDefinition(item)
	if not item:GetAttribute("Pet") and not item:GetAttribute("PetId") then
		return nil
	end

	local petName = getPetName(item)
	local itemKey = item:GetAttribute("PetId") or item:GetAttribute("Id") or item.Name
	return getDefinition("Pet", petName), "Pets", itemKey, 1, petName
end

local function inferGearName(item)
	local attributeNames = {
		"GearTool", "Gear", "WateringCan", "Sprinkler", "Mushroom", "Gnome", "Trowel", "Prop", "EmptyPot", "Pot"
	}

	for _, attributeName in ipairs(attributeNames) do
		local value = item:GetAttribute(attributeName)
		if type(value) == "string" and value ~= "" then
			return value, attributeName
		end
	end

	return parseNameBeforeBracket(item.Name), nil
end

local function inferGearCategory(gearName, attributeName)
	if attributeName == "WateringCan" then
		return "WateringCans"
	elseif attributeName == "Sprinkler" then
		return "Sprinklers"
	elseif attributeName == "Mushroom" then
		return "Mushrooms"
	elseif attributeName == "Gnome" then
		return "Gnomes"
	elseif attributeName == "Trowel" then
		return "Trowels"
	elseif attributeName == "EmptyPot" or attributeName == "Pot" then
		return "EmptyPots"
	end

	return GearCategoryByName[gearName] or "Props"
end

local function getGearDefinition(item)
	if item:GetAttribute("MainCategory") ~= "Gear"
		and not item:GetAttribute("GearTool")
		and not item:GetAttribute("Gear")
		and not item:GetAttribute("WateringCan")
		and not item:GetAttribute("Sprinkler")
		and not item:GetAttribute("Mushroom")
		and not item:GetAttribute("Gnome")
		and not item:GetAttribute("Trowel")
		and not item:GetAttribute("Prop")
		and not item:GetAttribute("EmptyPot")
		and not item:GetAttribute("Pot") then
		return nil
	end

	local gearName, attributeName = inferGearName(item)
	local definition = getDefinition("Gear", gearName)
	if not definition then
		return nil
	end

	local category = inferGearCategory(gearName, attributeName)
	local count = tonumber(item:GetAttribute("Count")) or 1
	return definition, category, gearName, count, gearName
end

local function getEggDefinition(item)
	local eggName = item:GetAttribute("Egg")
		or item:GetAttribute("EggName")
		or item:GetAttribute("PetEgg")
		or item:GetAttribute("ItemName")

	if type(eggName) ~= "string" or eggName == "" then
		if item:GetAttribute("MainCategory") == "Egg" or item:GetAttribute("ItemType") == "Egg" then
			eggName = parseNameBeforeBracket(item.Name)
		else
			return nil
		end
	end

	local definition = getDefinition("Egg", eggName)
	if not definition then
		return nil
	end

	local count = tonumber(item:GetAttribute("Count")) or 1
	return definition, "Eggs", eggName, count, eggName
end

local function getSelectedItemsFromBackpack()
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	local batch = {}
	local remaining = {}

	for _, definition in ipairs(Definitions) do
		if State.Selected[definition] then
			local count = getCount(definition)
			if count > 0 then
				remaining[definition] = count
			end
		end
	end

	if not backpack then
		return batch, "Backpack not found"
	end

	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			local definition, category, itemKey, stackCount, displayName = getPlantDefinition(item)
			if not definition then
				definition, category, itemKey, stackCount, displayName = getPetDefinition(item)
			end
			if not definition then
				definition, category, itemKey, stackCount, displayName = getGearDefinition(item)
			end
			if not definition then
				definition, category, itemKey, stackCount, displayName = getEggDefinition(item)
			end

			if definition and remaining[definition] and remaining[definition] > 0 then
				local sendCount = math.min(tonumber(stackCount) or 1, remaining[definition])
				if sendCount > 0 then
					addBatchItem(batch, category, itemKey, sendCount, displayName or definition.Name)
					remaining[definition] = remaining[definition] - sendCount
				end
			end
		end
	end

	return batch
end

local sending = false
connect(SendButton.Activated, function()
	if sending then
		return
	end
	sending = true
	SendButton.Text = "Sending..."
	setStatus("Preparing selected items...", Color3.fromRGB(230, 218, 160))

	local targetName = trim(TargetBox.Text)
	if targetName == "" then
		setStatus("Target username is empty", Color3.fromRGB(255, 150, 150))
		addHistory("Failed", "-", {}, "Target username is empty")
		SendButton.Text = "Send Selected Items"
		sending = false
		return
	end

	if not Networking or not Networking.Mailbox or not Networking.Mailbox.SendBatch then
		setStatus("Mailbox networking not found", Color3.fromRGB(255, 150, 150))
		addHistory("Failed", targetName, {}, "Mailbox networking not found")
		SendButton.Text = "Send Selected Items"
		sending = false
		return
	end

	local targetUserId
	local okLookup, lookupResult, lookupName = pcall(function()
		if Networking.Mailbox.LookupPlayer then
			return Networking.Mailbox.LookupPlayer:Fire(targetName)
		end
		return Players:GetUserIdFromNameAsync(targetName), targetName
	end)

	if okLookup and type(lookupResult) == "number" and lookupResult > 0 then
		targetUserId = lookupResult
		if type(lookupName) == "string" and lookupName ~= "" then
			targetName = lookupName
		end
	end

	if not targetUserId then
		local okUser, userError = pcall(function()
			targetUserId = Players:GetUserIdFromNameAsync(targetName)
		end)
		if not okUser or not targetUserId then
			setStatus("Target not found: " .. targetName, Color3.fromRGB(255, 150, 150))
			addHistory("Failed", targetName, {}, tostring(userError or "Target not found"))
			SendButton.Text = "Send Selected Items"
			sending = false
			return
		end
	end

	local batch, batchError = getSelectedItemsFromBackpack()
	if batchError then
		setStatus(batchError, Color3.fromRGB(255, 150, 150))
		addHistory("Failed", targetName, batch, batchError)
		SendButton.Text = "Send Selected Items"
		sending = false
		return
	end

	if #batch == 0 then
		setStatus("No selected items found in backpack", Color3.fromRGB(255, 150, 150))
		addHistory("Failed", targetName, batch, "No selected items found in backpack")
		SendButton.Text = "Send Selected Items"
		sending = false
		return
	end

	local sendPayload = stripPrivateFields(batch)
	local okSend, result, message = pcall(function()
		return Networking.Mailbox.SendBatch:Fire(targetUserId, sendPayload, NoteBox.Text)
	end)

	if okSend and result then
		local detail
		if type(message) == "string" and message ~= "" then
			detail = message
		else
			detail = "UserId " .. tostring(targetUserId)
		end
		setStatus("Sent to " .. targetName .. ": " .. summarizeBatch(batch), Color3.fromRGB(170, 255, 190))
		addHistory("Sent", targetName, batch, detail)
	elseif okSend then
		local detail
		if type(message) == "string" and message ~= "" then
			detail = message
		else
			detail = "Server rejected"
		end
		setStatus("Send failed: " .. detail, Color3.fromRGB(255, 150, 150))
		addHistory("Failed", targetName, batch, detail)
	else
		setStatus("Send failed: " .. tostring(result), Color3.fromRGB(255, 150, 150))
		addHistory("Failed", targetName, batch, tostring(result))
	end

	SendButton.Text = "Send Selected Items"
	sending = false
end)

connect(SearchBox:GetPropertyChangedSignal("Text"), updateSearch)

connect(SelectVisibleButton.Activated, function()
	for _, definition in ipairs(Definitions) do
		local rowInfo = State.Rows[definition]
		if rowInfo and rowInfo.Frame.Visible then
			State.Selected[definition] = true
			updateRowText(definition)
		end
	end
	refreshSelectedCount()
end)

connect(ClearButton.Activated, function()
	for _, definition in ipairs(Definitions) do
		State.Selected[definition] = false
		updateRowText(definition)
	end
	refreshSelectedCount()
end)

connect(CloseButton.Activated, function()
	Gui.Enabled = false
end)

local dragging = false
local dragInput
local dragStart
local startPosition

connect(Header.InputBegan, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = Main.Position
		connect(input.Changed, function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

connect(Header.InputChanged, function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

connect(UserInputService.InputChanged, function(input)
	if dragging and input == dragInput then
		local delta = input.Position - dragStart
		Main.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
end)

refreshSelectedCount()
