function love.load()
    love.window.setTitle("Domino Deckbuilder")
    
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    
    if love.system.getOS() == "Android" or love.system.getOS() == "iOS" then
        love.window.setFullscreen(true)
        screenWidth = love.graphics.getWidth()
        screenHeight = love.graphics.getHeight()
    else
        -- Enable window resizing for desktop platforms
        love.window.setMode(screenWidth, screenHeight, {resizable = true})
    end
    
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    require("game.domino")
    require("game.hand")
    require("game.board")
    require("game.validation")
    require("game.scoring")
    require("game.challenges")
    require("game.map")
    require("ui.touch")
    require("ui.layout")
    require("ui.fonts")
    require("ui.colors")
    require("ui.renderer")
    require("ui.animation")
    require("ui.audio")
    
    loadDominoSprites()
    loadDemonTileSprites()
    loadNodeSprites()
    loadCoinSprite()
    
    gameState = {
        screen = {
            width = screenWidth,
            height = screenHeight,
            scale = math.min(screenWidth / 800, screenHeight / 600)
        },
        deck = {},
        hand = {},
        board = {},
        placedTiles = {},
        score = 0,
        gamePhase = "playing",
        placementOrder = {},
        discardsUsed = 0,
        playsUsed = 0,
        handsPlayed = 0,
        currentRound = 1,
        baseTargetScore = 3,
        targetScore = 3,
        maxHandsPerRound = 3,
        scoringSequence = nil,
        currentMap = nil,
        selectedNode = nil,  -- For node confirmation dialog
        isBossRound = false,  -- Track if current combat is the boss round
        scoreAnimation = {    -- Animation properties for score display
            scale = 1.0,
            shake = 0,
            color = {UI.Colors.FONT_RED[1], UI.Colors.FONT_RED[2], UI.Colors.FONT_RED[3], UI.Colors.FONT_RED[4]}
        },
        -- Currency system
        coins = 0,  -- Starting currency
        startRoundCoins = 0,  -- Coins at start of round for bonus calculation
        coinsAnimation = {    -- Animation properties for coins display
            scale = 1.0,
            shake = 0,
            color = {1, 0.9, 0.3, 1},  -- Gold color
            coinFlips = {},  -- Random horizontal flips for each coin sprite
            fallingCoins = {},  -- Array of coins currently animating
            settledCoins = 0,  -- Number of coins that finished animating
            targetCoins = 0  -- Final target coin count
        },
        -- Deckbuilding system
        tileCollection = {},  -- All tiles the player has unlocked
        offeredTiles = {},    -- Tiles currently being offered in tiles menu
        selectedTileOffer = nil,  -- Currently selected tile in the offering
        selectedTilesToBuy = {},  -- Tiles selected for purchase (multi-select)
        -- Challenge system
        activeChallenges = {},  -- Active challenges for current combat
        challengeStates = {},  -- State data for each challenge
        -- Settings system
        settingsMenuOpen = false,  -- Track if settings menu is open
        musicEnabled = true  -- Track music state
    }
    
    UI.Fonts.load()
    UI.Audio.load()

    -- Load CRT shader and create render canvas
    crtShader = love.graphics.newShader("shaders/background_crt.glsl")
    mainCanvas = love.graphics.newCanvas(screenWidth, screenHeight, {format = "rgba8", readable = true, msaa = 0})

    initializeGame()

    -- Start background music
    UI.Audio.playMusic()
end

function initializeGame(isNewRound)
    isNewRound = isNewRound or false
    
    -- Initialize tile collection on first run
    if not gameState.tileCollection or #gameState.tileCollection == 0 then
        gameState.tileCollection = Domino.createStarterCollection()
    end
    
    -- Create deck from player's collection
    gameState.deck = Domino.createDeckFromCollection(gameState.tileCollection)
    Domino.shuffleDeck(gameState.deck)
    
    -- Initialize empty hand first
    gameState.hand = {}
    
    -- Draw tiles from deck
    for i = 1, 7 do
        local tile = table.remove(gameState.deck, 1)
        if tile then
            tile.selected = false
            tile.placed = false
            table.insert(gameState.hand, tile)
        end
    end
    
    gameState.board = {}
    gameState.placedTiles = {}
    gameState.score = 0
    gameState.previousScore = 0
    gameState.selectedTiles = {}
    gameState.placementOrder = {}
    gameState.discardsUsed = 0
    gameState.playsUsed = 0
    gameState.handsPlayed = 0
    gameState.scoreAnimation = nil
    gameState.buttonAnimations = {
        playButton = {scale = 1.0, pressed = false},
        discardButton = {scale = 1.0, pressed = false}
    }
    
    -- If not a new round, reset everything including round progress
    if not isNewRound then
        gameState.currentRound = 1
        gameState.targetScore = gameState.baseTargetScore
    else
        -- Calculate target score for current round (doubles each round)
        gameState.targetScore = gameState.baseTargetScore * (2 ^ (gameState.currentRound - 1))
    end
    
    -- Position tiles will be handled in first draw call
end

function initializeCombatRound()
    -- Reset only combat-specific state while preserving map progress and tile collection

    -- STEP 1: Clear old combat state FIRST
    gameState.board = {}
    gameState.placedTiles = {}
    gameState.hand = {}
    gameState.score = 0
    gameState.previousScore = 0
    gameState.selectedTiles = {}
    gameState.placementOrder = {}
    gameState.discardsUsed = 0
    gameState.playsUsed = 0
    gameState.handsPlayed = 0
    gameState.scoreAnimation = nil
    gameState.buttonAnimations = {
        playButton = {scale = 1.0, pressed = false},
        discardButton = {scale = 1.0, pressed = false}
    }

    -- Track coins at start of round for bonus calculation
    gameState.startRoundCoins = gameState.coins

    -- STEP 2: Create fresh deck from player's collection
    gameState.deck = Domino.createDeckFromCollection(gameState.tileCollection)
    Domino.shuffleDeck(gameState.deck)

    -- STEP 3: Initialize challenges (can now take a tile from deck for anchor)
    Challenges.initialize(gameState)

    -- STEP 4: Draw tiles from deck to hand
    for i = 1, 7 do
        local tile = table.remove(gameState.deck, 1)
        if tile then
            tile.selected = false
            tile.placed = false
            table.insert(gameState.hand, tile)
        end
    end

    -- STEP 5: Arrange board tiles (including anchor) to ensure proper positioning
    if #gameState.placedTiles > 0 then
        Board.arrangePlacedTiles()
    end

    -- Keep currentRound, targetScore, currentMap, and tileCollection unchanged
    -- These should persist across combat rounds
end

function updateScore(newScore, bonusInfo)
    if newScore ~= gameState.score then
        local difference = newScore - gameState.score
        gameState.previousScore = gameState.score
        gameState.score = newScore
        
        -- Create score popup animation
        local scoreX = gameState.screen.width - UI.Layout.scale(120)
        local scoreY = UI.Layout.scale(50)
        
        UI.Animation.createScorePopup(difference, scoreX, scoreY, bonusInfo and bonusInfo.hasBonus)
        
        -- Animate the score display itself
        gameState.scoreAnimation = {
            scale = 1.0,
            shake = 0,
            color = {UI.Colors.FONT_RED[1], UI.Colors.FONT_RED[2], UI.Colors.FONT_RED[3], UI.Colors.FONT_RED[4]}
        }
        
        local color = UI.Colors.FONT_RED
        if bonusInfo and bonusInfo.hasBonus then
            color = UI.Colors.FONT_RED_DARK
            gameState.scoreAnimation.shake = 3
        end
        
        UI.Animation.animateTo(gameState.scoreAnimation, {scale = 1.3}, 0.2, "easeOutBack", function()
            UI.Animation.animateTo(gameState.scoreAnimation, {scale = 1.0}, 0.3, "easeOutQuart")
            gameState.scoreAnimation.color = {color[1], color[2], color[3], color[4]}
            UI.Animation.animateTo(gameState.scoreAnimation, {shake = 0}, 0.5, "easeOutQuart", function()
                UI.Animation.animateTo(gameState.scoreAnimation.color, {[1] = UI.Colors.FONT_RED[1], [2] = UI.Colors.FONT_RED[2], [3] = UI.Colors.FONT_RED[3]}, 1.0, "easeOutQuart")
            end)
        end)
    end
end

function updateCoins(newCoins, bonusInfo)
    local difference = newCoins - gameState.coins

    if difference > 0 then
        -- Gaining coins - trigger falling animation
        gameState.coinsAnimation.targetCoins = newCoins

        -- Get base position from layout (separate text and stack positions)
        local textX, textY, stackX, stackY = UI.Layout.getCoinDisplayPosition()
        local minScale = math.min(gameState.screen.width / 800, gameState.screen.height / 600)
        local spriteScale = math.max(minScale * 2.0, 1.0)

        -- Create falling coin objects for each new coin
        local oldCoins = gameState.coins
        for i = 1, difference do
            local coinIndex = oldCoins + i

            -- Calculate target position in stack
            local stackIndex = math.floor((coinIndex - 1) / 15)
            local coinInStack = ((coinIndex - 1) % 15) + 1

            local coinStartX = stackX  -- Stack starts at stack position
            local stackOffsetX = stackIndex * (8 * spriteScale)  -- Move RIGHT for new stacks
            local targetX = coinStartX + stackOffsetX
            local targetY = stackY - ((coinInStack - 1) * 4 * spriteScale)

            -- Random horizontal starting offset for variety
            local randomXOffset = (love.math.random() - 0.5) * UI.Layout.scale(100)

            table.insert(gameState.coinsAnimation.fallingCoins, {
                index = coinIndex,
                startY = -UI.Layout.scale(100),  -- Off-screen top
                currentY = -UI.Layout.scale(100),
                targetY = targetY,
                startX = targetX + randomXOffset,
                currentX = targetX + randomXOffset,
                targetX = targetX,
                elapsed = 0,
                startDelay = (i - 1) * 0.08,  -- 80ms stagger per coin
                duration = 0.5,
                settleElapsed = 0,
                settleDuration = 0.25,
                phase = "waiting",  -- "waiting", "falling", "settling", "settled"
                xFlip = love.math.random() > 0.5,
                stackIndex = stackIndex,
                coinInStack = coinInStack
            })
        end

        -- Keep existing popup
        local coinX = UI.Layout.scale(60)
        local coinY = gameState.screen.height - UI.Layout.scale(120)
        UI.Animation.createScorePopup(difference, coinX, coinY, bonusInfo and bonusInfo.hasBonus)

    elseif difference < 0 then
        -- Losing coins - instant update (no animation needed)
        gameState.coins = newCoins
        gameState.coinsAnimation.settledCoins = newCoins
        gameState.coinsAnimation.targetCoins = newCoins

        -- Regenerate flips
        gameState.coinsAnimation.coinFlips = {}
        for i = 1, newCoins do
            gameState.coinsAnimation.coinFlips[i] = love.math.random() > 0.5
        end
    end
end

function updateFallingCoins(dt)
    if not gameState.coinsAnimation.fallingCoins then return end

    local allSettled = true

    for i = #gameState.coinsAnimation.fallingCoins, 1, -1 do
        local coin = gameState.coinsAnimation.fallingCoins[i]

        if coin.phase == "waiting" then
            coin.elapsed = coin.elapsed + dt
            if coin.elapsed >= coin.startDelay then
                coin.phase = "falling"
                coin.elapsed = 0
            end
            allSettled = false

        elseif coin.phase == "falling" then
            coin.elapsed = coin.elapsed + dt
            local progress = math.min(coin.elapsed / coin.duration, 1.0)

            -- Ease out cubic for falling motion
            local easedProgress = 1 - math.pow(1 - progress, 3)

            -- Update Y position (falling down)
            coin.currentY = coin.startY + (coin.targetY - coin.startY) * easedProgress

            -- Update X position (drift toward target)
            coin.currentX = coin.startX + (coin.targetX - coin.startX) * easedProgress

            if progress >= 1.0 then
                coin.phase = "settling"
                coin.settleElapsed = 0
                coin.currentY = coin.targetY
                coin.currentX = coin.targetX

                -- Play sound effect here if you have one
            end
            allSettled = false

        elseif coin.phase == "settling" then
            coin.settleElapsed = coin.settleElapsed + dt
            local progress = math.min(coin.settleElapsed / coin.settleDuration, 1.0)

            -- Bounce effect using easeOutBack
            local c1 = 1.70158
            local c3 = c1 + 1
            local bounce = 1 + c3 * math.pow(progress - 1, 3) + c1 * math.pow(progress - 1, 2)

            -- Slight downward bounce
            coin.currentY = coin.targetY + (10 * (1 - bounce))

            if progress >= 1.0 then
                coin.phase = "settled"
                coin.currentY = coin.targetY

                -- Increment settled count and actual coin count
                gameState.coinsAnimation.settledCoins = gameState.coinsAnimation.settledCoins + 1
                gameState.coins = gameState.coinsAnimation.settledCoins

                -- Store flip state
                gameState.coinsAnimation.coinFlips[coin.index] = coin.xFlip

                -- Remove from falling array
                table.remove(gameState.coinsAnimation.fallingCoins, i)
            end
            allSettled = false
        end
    end

    -- Clean up when all settled
    if allSettled and #gameState.coinsAnimation.fallingCoins == 0 then
        gameState.coinsAnimation.settledCoins = gameState.coinsAnimation.targetCoins
        gameState.coins = gameState.coinsAnimation.targetCoins
    end
end

function startScoringSequence(tiles)
    gameState.scoringSequence = {
        tiles = tiles,
        currentTileIndex = 1,
        accumulatedValue = 0,
        showingMultiplier = false,
        showingFinal = false,
        phase = "scoring_tiles",  -- "scoring_tiles", "multiplying", "final"
        timer = 0,
        tileAnimDelay = 0.4,
        finalTileAnimating = false,
        waitingForFinalTile = false
    }

    -- Sort tiles from left to right for visual consistency
    table.sort(gameState.scoringSequence.tiles, function(a, b)
        return a.x < b.x
    end)
end

function updateScoringSequence(dt)
    if not gameState.scoringSequence then return end
    
    local seq = gameState.scoringSequence
    seq.timer = seq.timer + dt
    
    if seq.phase == "scoring_tiles" then
        -- Check if we're waiting for final tile to finish
        if seq.waitingForFinalTile and not seq.finalTileAnimating then
            -- Final tile finished, move to multiplier phase
            seq.phase = "multiplying"
            seq.showingMultiplier = true
            seq.timer = 0
            seq.waitingForFinalTile = false
        else
            -- Check if it's time to animate the next tile
            local tileDelay = (seq.currentTileIndex - 1) * seq.tileAnimDelay
            
            if seq.timer >= tileDelay then
                if seq.currentTileIndex <= #seq.tiles then
                    local tile = seq.tiles[seq.currentTileIndex]
                    
                    -- Add this tile's value to accumulated
                    local tileValue = Domino.getValue(tile)
                    local isDouble = Domino.isDouble(tile)
                    seq.accumulatedValue = seq.accumulatedValue + tileValue + (isDouble and 10 or 0)
                    
                    -- Animate the tile with shake effect
                    animateTileScoring(tile)
                    
                    seq.currentTileIndex = seq.currentTileIndex + 1
                else
                    -- All tiles have been triggered, wait for final tile to finish animating
                    seq.waitingForFinalTile = true
                end
            end
        end
    elseif seq.phase == "multiplying" then
        -- Immediately move to final result
        seq.phase = "final"
        seq.showingFinal = true
        seq.timer = 0
    elseif seq.phase == "final" then
        -- Immediately complete the scoring sequence
        completeScoringSequence()
    end
end

function animateTileScoring(tile)
    -- Create satisfying punch-out shake effect
    tile.scoreScale = tile.scoreScale or 1.0
    tile.scoreShake = tile.scoreShake or 0

    -- Play tile sound for audio feedback
    UI.Audio.playTilePlaced()

    local seq = gameState.scoringSequence
    local isFinalTile = (seq.currentTileIndex == #seq.tiles)
    
    if isFinalTile then
        seq.finalTileAnimating = true
    end
    
    UI.Animation.animateTo(tile, {scoreScale = 1.15}, 0.15, "easeOutBack", function()
        UI.Animation.animateTo(tile, {scoreScale = 1.0}, 0.25, "easeOutBack", function()
            -- If this was the final tile, mark that it's done animating
            if isFinalTile then
                seq.finalTileAnimating = false
            end
        end)
    end)
    
    -- Add shake effect
    tile.scoreShake = 5
    UI.Animation.animateTo(tile, {scoreShake = 0}, 0.3, "easeOutQuart")
    
    -- Animate the formula counter as well
    seq.formulaAnimation = seq.formulaAnimation or {scale = 1.0, shake = 0}
    seq.formulaAnimation.scale = 1.0
    seq.formulaAnimation.shake = 3
    
    UI.Animation.animateTo(seq.formulaAnimation, {scale = 1.2}, 0.1, "easeOutBack", function()
        UI.Animation.animateTo(seq.formulaAnimation, {scale = 1.0}, 0.2, "easeOutBack")
    end)
    UI.Animation.animateTo(seq.formulaAnimation, {shake = 0}, 0.3, "easeOutQuart")
end

function completeScoringSequence()
    local tiles = gameState.scoringSequence.tiles
    local score = Scoring.calculateScore(tiles)
    local breakdown = Scoring.getScoreBreakdown(tiles)
    
    -- Add celebration text for successful plays
    local centerX = gameState.screen.width / 2
    local centerY = gameState.screen.height / 2
    local hasBonus = breakdown.multiplier > 1 or breakdown.doubleBonus > 0
    
    if hasBonus then
        UI.Animation.createFloatingText("NICE COMBO!", centerX, centerY, {
            color = {1, 0.8, 0.2, 1},
            fontSize = "large",
            duration = 2.5,
            riseDistance = 100,
            startScale = 0.3,
            endScale = 1.8,
            bounce = true,
            easing = "easeOutElastic"
        })
    elseif #tiles >= 3 then
        UI.Animation.createFloatingText("GOOD PLAY!", centerX, centerY, {
            color = {0.2, 0.9, 0.3, 1},
            fontSize = "medium",
            duration = 2.0,
            riseDistance = 80,
            startScale = 0.5,
            endScale = 1.4,
            bounce = true,
            easing = "easeOutBack"
        })
    end
    
    -- Update the actual game score
    updateScore(gameState.score + score, {hasBonus = hasBonus})
    
    -- Clear scoring sequence state
    gameState.scoringSequence = nil
    
    -- Continue with normal game flow (refill hand, etc.)
    gameState.handsPlayed = gameState.handsPlayed + 1

    -- Call challenge hand complete handlers
    if Challenges then
        Challenges.onHandComplete(gameState)
    end

    -- Remove tiles from hand and placed tiles
    -- First mark the tiles as selected so they can be removed
    for _, placedTile in ipairs(tiles) do
        for _, handTile in ipairs(gameState.hand) do
            if handTile.id == placedTile.id then
                handTile.selected = true
                break
            end
        end
    end

    Hand.removeSelectedTiles(gameState.hand)

    -- Clear placed tiles but preserve anchor tile if it exists
    local anchorTile = Challenges and Challenges.getAnchorTile(gameState)
    gameState.placedTiles = {}

    if anchorTile then
        -- Re-add anchor tile to placed tiles so it persists
        table.insert(gameState.placedTiles, anchorTile)
        -- Re-position anchor tile at center
        Board.arrangePlacedTiles()
    end

    -- Refill hand
    Hand.refillHand(gameState.hand, gameState.deck, 7)

    -- Check game end condition
    Touch.checkGameEnd()
end

function animateButtonPress(buttonName)
    if gameState.buttonAnimations and gameState.buttonAnimations[buttonName] then
        local button = gameState.buttonAnimations[buttonName]
        button.pressed = true
        
        UI.Animation.animateTo(button, {scale = 0.9}, 0.1, "easeOutQuart", function()
            UI.Animation.animateTo(button, {scale = 1.1}, 0.15, "easeOutBack", function()
                UI.Animation.animateTo(button, {scale = 1.0}, 0.2, "easeOutQuart", function()
                    button.pressed = false
                end)
            end)
        end)
    end
end

function love.update(dt)
    Touch.update(dt)
    UI.Animation.update(dt)
    UI.Renderer.updateEyeBlinks(dt)
    updateFallingCoins(dt)

    if gameState.gamePhase == "playing" then
        Hand.update(dt)
        Board.update(dt)
        updateScoringSequence(dt)
    end
end

function love.draw()
    -- PASS 1: Render entire game to canvas
    love.graphics.setCanvas(mainCanvas)
    -- Don't clear here - let each screen phase handle its own background properly
    
    UI.Layout.begin()
    
    -- Each phase draws its own background as before
    if gameState.gamePhase == "playing" or gameState.gamePhase == "won" then
        UI.Renderer.drawBackground()
        UI.Renderer.drawBoard(gameState.board)
        UI.Renderer.drawPlacedTiles()
        UI.Renderer.drawHand(gameState.hand)
        UI.Renderer.drawScore(gameState.score)
        UI.Renderer.drawUI()
        UI.Renderer.drawCoins()
        UI.Renderer.drawSettingsButton()
        UI.Renderer.drawSettingsMenu()
        -- Draw game over overlay for won state (button only, no full overlay)
        if gameState.gamePhase == "won" then
            UI.Renderer.drawGameOver()
        end
    elseif gameState.gamePhase == "map" then
        UI.Renderer.drawMap()
    elseif gameState.gamePhase == "node_confirmation" then
        UI.Renderer.drawMap()  -- Draw map background
        UI.Renderer.drawNodeConfirmation()  -- Draw confirmation dialog on top
    elseif gameState.gamePhase == "tiles_menu" then
        UI.Renderer.drawTilesMenu()
    elseif gameState.gamePhase == "artifacts_menu" then
        UI.Renderer.drawArtifactsMenu()
    elseif gameState.gamePhase == "contracts_menu" then
        UI.Renderer.drawContractsMenu()
    elseif gameState.gamePhase == "lost" then
        UI.Renderer.drawGameOver()
    end
    
    UI.Animation.drawFloatingTexts()
    
    UI.Layout.finish()
    
    -- PASS 2: Apply CRT shader and render canvas to screen
    love.graphics.setCanvas()  -- Reset to screen
    
    -- Ensure proper color and blend state before applying shader
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")
    love.graphics.setShader(crtShader)
    
    -- Set shader uniforms
    crtShader:send("time", love.timer.getTime())
    crtShader:send("resolution", {gameState.screen.width, gameState.screen.height})
    
    -- Draw the canvas to screen through CRT shader
    love.graphics.draw(mainCanvas, 0, 0)
    
    -- Reset shader and state
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
end

function love.resize(w, h)
    gameState.screen.width = w
    gameState.screen.height = h
    gameState.screen.scale = math.min(w / 800, h / 600)
    
    -- Recreate canvas with new dimensions for CRT shader
    if mainCanvas then
        mainCanvas:release()
    end
    mainCanvas = love.graphics.newCanvas(w, h, {format = "rgba8", readable = true, msaa = 0})
    
    UI.Fonts.recalculate()
    
    -- Force layout recalculation for orientation changes
    UI.Layout.recalculate()
    
    -- Update hand positions for responsive layout
    if gameState.hand then
        Hand.updatePositions(gameState.hand)
    end
    
    -- Rearrange board tiles for new screen dimensions
    if gameState.placedTiles and #gameState.placedTiles > 0 then
        Board.arrangePlacedTiles()
    end
end

function love.mousepressed(x, y, button, istouch)
    if istouch or button == 1 then
        Touch.pressed(x, y, istouch)
    end
end

function love.mousereleased(x, y, button, istouch)
    if istouch or button == 1 then
        Touch.released(x, y, istouch)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    Touch.moved(x, y, dx, dy, istouch)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
    Touch.pressed(x, y, true, id)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    Touch.released(x, y, true, id)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    Touch.moved(x, y, dx, dy, true, id)
end

function loadDominoSprites()
    dominoSprites = {}
    dominoTiltedSprites = {}
    
    -- Load vertical sprites (for hand tiles)
    for i = 0, 6 do
        for j = i, 6 do
            local filename = "sprites/tiles/" .. i .. j .. ".png"
            if love.filesystem.getInfo(filename) then
                local sprite = love.graphics.newImage(filename)
                dominoSprites[i .. j] = sprite
            end
        end
    end
    
    -- Load tilted sprites (for board tiles) - note: folder was titled_tiles, likely meant to be tilted_tiles
    local rawTiltedSprites = {}
    for i = 0, 6 do
        for j = i, 6 do
            local filename = "sprites/titled_tiles/" .. i .. j .. "t.png"
            if love.filesystem.getInfo(filename) then
                local sprite = love.graphics.newImage(filename)
                rawTiltedSprites[i .. j] = sprite
            end
        end
    end
    
    -- Create mapping for all possible domino combinations (vertical sprites)
    for i = 0, 6 do
        for j = 0, 6 do
            local key = i .. j
            if not dominoSprites[key] then
                -- Try inverted version (j-i instead of i-j)
                local invertedKey = j .. i
                if dominoSprites[invertedKey] then
                    -- Mark this sprite as needing 180-degree rotation
                    dominoSprites[key] = {
                        sprite = dominoSprites[invertedKey],
                        inverted = true
                    }
                end
            elseif dominoSprites[key] then
                -- Wrap existing sprites in consistent format
                local existingSprite = dominoSprites[key]
                dominoSprites[key] = {
                    sprite = existingSprite,
                    inverted = false
                }
            end
        end
    end
    
    -- Create mapping for all tilted sprite combinations
    for i = 0, 6 do
        for j = 0, 6 do
            local key = i .. j
            local minVal = math.min(i, j)
            local maxVal = math.max(i, j)
            local spriteKey = minVal .. maxVal
            
            -- Check if we have the base sprite (e.g., "14" for both "14" and "41")
            local baseSprite = rawTiltedSprites[spriteKey]
            if baseSprite then
                -- Create entries for both orientations
                dominoTiltedSprites[spriteKey] = {
                    sprite = baseSprite,
                    flipped = false  -- Normal orientation (smaller number left)
                }
                
                -- If it's not a double, create the flipped version
                if minVal ~= maxVal then
                    local flippedKey = maxVal .. minVal
                    dominoTiltedSprites[flippedKey] = {
                        sprite = baseSprite,
                        flipped = true  -- Flipped orientation (larger number left)
                    }
                end
            end
        end
    end
end

function loadDemonTileSprites()
    demonTileSprites = {}

    -- Load base demon tile sprites
    local tiltedFilename = "sprites/demon_tiles/tilted_demon_tile.png"
    if love.filesystem.getInfo(tiltedFilename) then
        demonTileSprites.tilted = love.graphics.newImage(tiltedFilename)
    end

    local verticalFilename = "sprites/demon_tiles/vertical_demon_tile.png"
    if love.filesystem.getInfo(verticalFilename) then
        demonTileSprites.vertical = love.graphics.newImage(verticalFilename)
    end

    -- Load eye animation frames
    demonTileSprites.eyeFrames = {}
    local eyeFiles = {"base.png", "blink1.png", "blink2.png", "blink3.png"}

    for i, filename in ipairs(eyeFiles) do
        local fullPath = "sprites/demon_tiles/eye_animation/" .. filename
        if love.filesystem.getInfo(fullPath) then
            table.insert(demonTileSprites.eyeFrames, love.graphics.newImage(fullPath))
        end
    end

    -- Also keep reference to base eye for backwards compatibility
    if #demonTileSprites.eyeFrames > 0 then
        demonTileSprites.eye = demonTileSprites.eyeFrames[1]
    end
end

function loadNodeSprites()
    nodeSprites = {}
    
    -- Define node type to sprite mapping
    local nodeTypeMapping = {
        combat = "combat",
        tiles = "tile",
        artifacts = "artifact", 
        contracts = "contract",
        start = "tile",  -- Fallback to tile sprite
        boss = "combat"  -- Fallback to combat sprite
    }
    
    -- Load base sprites and selected sprites for each node type
    for nodeType, spriteName in pairs(nodeTypeMapping) do
        -- Load base sprite
        local baseFilename = "sprites/nodes/" .. spriteName .. ".png"
        if love.filesystem.getInfo(baseFilename) then
            local baseSprite = love.graphics.newImage(baseFilename)
            
            -- Load selected sprite
            local selectedFilename = "sprites/nodes/" .. spriteName .. "_selected.png"
            local selectedSprite = nil
            if love.filesystem.getInfo(selectedFilename) then
                selectedSprite = love.graphics.newImage(selectedFilename)
            end
            
            nodeSprites[nodeType] = {
                base = baseSprite,
                selected = selectedSprite
            }
        end
    end
end

function loadCoinSprite()
    local coinFilename = "sprites/currency/coin.png"
    if love.filesystem.getInfo(coinFilename) then
        coinSprite = love.graphics.newImage(coinFilename)
    end
end