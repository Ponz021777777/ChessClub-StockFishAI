local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Chess Club Stockfish",
    LoadingTitle = "Initializing Stockfish",
    LoadingSubtitle = "Stockfish",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local MainTab = Window:CreateTab("Automation", nil)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local NetFolder = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("RbxUtil"):WaitForChild("Net")
local GameStartedEvent = NetFolder:WaitForChild("RE/GameStarted")
local PiecesFolder = LocalPlayer.PlayerGui:WaitForChild("2DBoard"):WaitForChild("Main"):WaitForChild("Pieces")

local SERVER_URL = "https://repl-creator--ponzjeronne.replit.app/api/get-best-move"

local IsAutomationEnabled = false
local EngineDepthSetting = 6       
local currentGameID = nil
local myColor = nil 
local moveConnection = nil 
local gameEndedConnection = nil

local pieceTypeMap = {
    White_Pawn = "P", White_Knight = "N", White_Bishop = "B", White_Rook = "R", White_Queen = "Q", White_King = "K",
    Black_Pawn = "p", Black_Knight = "n", Black_Bishop = "b", Black_Rook = "r", Black_Queen = "q", Black_King = "k"
}

-- Best-effort device identifier, used only so the dashboard can tell
-- different users apart in the recent-activity log. Different executors
-- expose this under different global names, so we try the common ones and
-- fall back to "unknown" if none are available.
local cachedHWID = nil
local function getHWID()
    if cachedHWID then return cachedHWID end

    local ok, hwid = pcall(function()
        if gethwid then return gethwid() end
        if get_hidden_hwid then return get_hidden_hwid() end
        if syn and syn.get_hwid then return syn.get_hwid() end
        if identifyexecutor then
            local name, version = identifyexecutor()
            return tostring(name) .. "-" .. tostring(version)
        end
        return nil
    end)

    cachedHWID = (ok and hwid) and tostring(hwid) or "unknown"
    return cachedHWID
end

local function getColumnIndex(letter)
    return string.byte(string.upper(letter)) - 64
end

local function generateFENFromPieces(whoseTurn)
    local grid = {}
    for r = 1, 8 do
        grid[r] = {}
        for c = 1, 8 do grid[r][c] = "." end
    end

    for _, pieceObject in pairs(PiecesFolder:GetChildren()) do
        if pieceObject:IsA("Instance") or pieceObject:IsA("GuiObject") then
            local tileValue = pieceObject:FindFirstChild("tile")
            if tileValue and tileValue.Value ~= "" and tileValue.Value ~= "Captured" then
                local tileStr = tileValue.Value
                local colLetter = string.sub(tileStr, 1, 1)
                local rowNum = tonumber(string.sub(tileStr, 2, 2))
                
                local col = getColumnIndex(colLetter)
                local row = rowNum
                local fenChar = pieceTypeMap[pieceObject.Name]
                
                if fenChar and row >= 1 and row <= 8 and col >= 1 and col <= 8 then
                    grid[row][col] = fenChar
                end
            end
        end
    end

    local fenRows = {}
    for r = 8, 1, -1 do
        local rowStr = ""
        local emptyCount = 0
        for c = 1, 8 do
            local char = grid[r][c]
            if char == "." then
                emptyCount = emptyCount + 1
            else
                if emptyCount > 0 then
                    rowStr = rowStr .. tostring(emptyCount)
                    emptyCount = 0
                end
                rowStr = rowStr .. char
            end
        end
        if emptyCount > 0 then rowStr = rowStr .. tostring(emptyCount) end
        table.insert(fenRows, rowStr)
    end

    local partialFen = table.concat(fenRows, "/")
    return partialFen .. " " .. whoseTurn .. " - - 0 1"
end

local function getStockfishMove(fenString)
    local payload = HttpService:JSONEncode({ fen = fenString, depth = EngineDepthSetting, hwid = getHWID() })
    local requestFunc = request or (http and http.request) or (syn and syn.request)
    if not requestFunc then return nil end

    local success, response = pcall(function()
        return requestFunc({
            Url = SERVER_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload
        })
    end)
    
    if success and response and response.StatusCode == 200 then
        local data = HttpService:JSONDecode(response.Body)
        return data.best_move
    else
        return nil
    end
end

local function sendOutcomeToServer(status)
    local requestFunc = request or (http and http.request) or (syn and syn.request)
    if not requestFunc then return end

    local payload = HttpService:JSONEncode({ status = status, hwid = getHWID() })
    pcall(function()
        requestFunc({
            Url = SERVER_URL:gsub("/get-best-move", "/game-over"),
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload
        })
    end)
end

local function submitMoveToServer(moveStr)
    if not currentGameID then return end
    local remoteName = "RE/SubmitMove_" .. currentGameID
    local submitRemote = NetFolder:FindFirstChild(remoteName)
    
    if submitRemote and submitRemote:IsA("RemoteEvent") then
        submitRemote:FireServer(moveStr)
    end
end

GameStartedEvent.OnClientEvent:Connect(function(gameData)
    if gameData and gameData.gameID then
        currentGameID = gameData.gameID
        
        if moveConnection then moveConnection:Disconnect() end
        if gameEndedConnection then gameEndedConnection:Disconnect() end
        
        if gameData.whiteName == LocalPlayer.Name then
            myColor = "w"
        else
            myColor = "b"
        end
        
        local moveMadeRemoteName = "RE/MoveMade_" .. currentGameID
        local MoveMadeEvent = NetFolder:WaitForChild(moveMadeRemoteName, 5)
        
        if MoveMadeEvent then
            moveConnection = MoveMadeEvent.OnClientEvent:Connect(function(...)
                if not IsAutomationEnabled then return end
                
                task.wait(0.3) 
                local currentFen = generateFENFromPieces(myColor)
                
                local randomHumanDelay = math.random(2, 20) / 10
                local startTime = os.clock()
                
                local bestMove = getStockfishMove(currentFen)
                local elapsedTime = os.clock() - startTime
                
                if elapsedTime < randomHumanDelay then
                    task.wait(randomHumanDelay - elapsedTime)
                end
                
                if bestMove and IsAutomationEnabled then 
                    submitMoveToServer(bestMove)
                end
            end)
        end
        
        local gameEndedRemoteName = "RE/GameEnded_" .. currentGameID
        local GameEndedEvent = NetFolder:WaitForChild(gameEndedRemoteName, 5)
        
        if GameEndedEvent then
            gameEndedConnection = GameEndedEvent.OnClientEvent:Connect(function(winnerName)
                if winnerName == LocalPlayer.Name then
                    sendOutcomeToServer("Win")
                else
                    sendOutcomeToServer("Loss/Draw")
                end
                
                if moveConnection then moveConnection:Disconnect() end
                if gameEndedConnection then gameEndedConnection:Disconnect() end
                currentGameID = nil
            end)
        end
        
        if myColor == "w" and gameData.whiteToPlay == true then
            task.spawn(function()
                task.wait(3) 
                if IsAutomationEnabled and currentGameID == gameData.gameID then
                    local startingFen = generateFENFromPieces("w")
                    local bestMove = getStockfishMove(startingFen)
                    if bestMove then 
                        submitMoveToServer(bestMove) 
                    end
                end
            end)
        end
    end
end)

local MasterToggle = MainTab:CreateToggle({
    Name = "Enable Engine Automation",
    CurrentValue = false,
    Flag = "MasterEngineSwitch",
    Callback = function(Value)
        IsAutomationEnabled = Value
    end,
})

local DepthSlider = MainTab:CreateSlider({
    Name = "Stockfish Search Depth (ELO Level)",
    Info = "Lower depth makes weaker moves faster. Higher depth makes grandmaster moves.",
    Range = { 1, 10 },
    Increment = 1,
    CurrentValue = 6,
    Flag = "EngineDepthSlider",
    Callback = function(Value)
        EngineDepthSetting = Value
    end,
})
