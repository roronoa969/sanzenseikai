--My PID is 7CSYm36srgRccmEFZIdir7pAaQQMnHmttMNBHjBaaII.
--Calculate points according to the three dimensions of health, energy and distance, 
--and select the appropriate player to attack based on the points sorting.
-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.

Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

function moveDirectionY(y, targetY)
    if y < targetY then
        return "Up"
    elseif y == targetY then
        return ""
    elseif y > targetY then
        return "Down"
    end
end

function moveDirectionX(x, targetX)
    if x < targetX then
        return "Right"
    elseif x == targetX then
        return ""
    elseif x > targetX then
        return "Left"
    end
end

-- Function to calculate score based on health, energy, and distance
function calculateScore(player, target)
    local healthScore = 100 - target.health                                         -- Higher health means lower healthScore
    local energyScore = target.energy
    local distanceScore = calculateDistance(player.x, player.y, target.x, target.y) -- Lower distance means higher distanceScore

    -- Calculate total score (you can adjust weights for each factor)
    local totalScore = healthScore + energyScore + (10 / (distanceScore + 1)) -- Adding 1 to avoid division by zero

    return totalScore
end

-- Decides the next action based on player proximity and scores.
function decideNextAction()
    local player = LatestGameState.Players[ao.id]

    -- Table to store scores for each player
    local playerScores = {}

    -- Calculate scores for each player (excluding self)
    for targetId, state in pairs(LatestGameState.Players) do
        if targetId ~= ao.id then
            local score = calculateScore(player, state)
            table.insert(playerScores, { id = targetId, score = score })
        end
    end

    -- Sort players by score (descending order)
    table.sort(playerScores, function(a, b) return a.score > b.score end)

    -- Attack the player with the highest score
    if #playerScores > 0 then
        local targetId = playerScores[1].id -- Get the player with the highest score
        local targetPlayer = LatestGameState.Players[targetId]

        print(colors.red .. "Attacking player with highest score." .. colors.reset)

        if targetId ~= ao.id and inRange(player.x, player.y, targetPlayer.x, targetPlayer.y, 3) then
            ao.send({
                Target = Game,
                Action = "PlayerAttack",
                Player = ao.id,
                TargetPlayer = targetId,
                AttackEnergy = tostring(player.energy)
            })
        else
            moveTarget(player, targetPlayer)
        end
    else
        print(colors.red .. "No viable target found. Moving randomly." .. colors.reset)
        moveRandomly()
    end

    InAction = false -- Reset InAction flag
end

-- Helper function: Calculate Euclidean distance between two points
function calculateDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

-- Helper function: Move target
function moveTarget(player, target)
    local dirX = moveDirectionX(player.x, target.x)
    local dirY = moveDirectionY(player.y, target.y)
    ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = dirY .. dirX })
end

-- Helper function: Move randomly
function moveRandomly()
    local directionMap = { "Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft" }
    local randomIndex = math.random(#directionMap)
    ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionMap[randomIndex] })
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            InAction = true  -- InAction logic added
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then -- InAction logic added
            print("Previous action still in progress. Skipping.")
        end
        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print \'LatestGameState\' for detailed view.")
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if LatestGameState.GameMode ~= "Playing" then
            InAction = false -- InAction logic added
            return
        end
        print("Deciding next action.")
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            local playerEnergy = LatestGameState.Players[ao.id].energy
            if playerEnergy == nil then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) })
            end
            InAction = false -- InAction logic added
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)



Send({ Target = Game, Action = "Register" })
Prompt = function() return Name .. "> " end
