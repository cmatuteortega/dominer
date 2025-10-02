Touch = {}

local touchState = {
    isPressed = false,
    startX = 0,
    startY = 0,
    currentX = 0,
    currentY = 0,
    dragThreshold = 15, -- Increased for mobile touch accuracy
    pressTime = 0,
    longPressTime = 0.5,
    touchId = nil,
    draggedTile = nil,
    draggedFrom = nil,
    draggedIndex = nil,
    -- Map dragging state
    isDraggingMap = false,
    mapDragStartCameraX = 0
}

-- Adjust drag threshold based on device type and context
local function getDragThreshold()
    local isMobile = UI.Layout.isMobile()
    local baseThreshold = touchState.dragThreshold
    
    -- Much lower threshold for map dragging to make it more responsive
    if gameState.gamePhase == "map" then
        -- Use very low threshold for PC (5 pixels) and somewhat low for mobile
        baseThreshold = isMobile and 10 or 5
    end
    
    return isMobile and math.max(20, baseThreshold * gameState.screen.scale) or baseThreshold
end

local function isInHandArea(x, y)
    local handArea = UI.Layout.getHandArea()
    return x >= handArea.x and x <= handArea.x + handArea.width and
           y >= handArea.y and y <= handArea.y + handArea.height
end

local function isInBoardArea(x, y)
    local boardArea = UI.Layout.getBoardArea()
    return x >= boardArea.x and x <= boardArea.x + boardArea.width and
           y >= boardArea.y and y <= boardArea.y + boardArea.height
end

local function getPlayButtonBounds()
    local buttonWidth, buttonHeight = UI.Layout.getButtonSize()
    local x, y = UI.Layout.getPlayButtonPosition()
    
    return {
        x = x,
        y = y,
        width = buttonWidth,
        height = buttonHeight
    }
end

local function getDiscardButtonBounds()
    local buttonWidth, buttonHeight = UI.Layout.getButtonSize()
    local x, y = UI.Layout.getDiscardButtonPosition()
    
    return {
        x = x,
        y = y,
        width = buttonWidth,
        height = buttonHeight
    }
end

local function isPointInRect(px, py, rect)
    return px >= rect.x and px <= rect.x + rect.width and
           py >= rect.y and py <= rect.y + rect.height
end

function Touch.update(dt)
    if touchState.isPressed then
        touchState.pressTime = touchState.pressTime + dt
    end
    
    -- Update dragged tile visual position with lag effect
    if touchState.draggedTile and touchState.draggedTile.isDragging then
        local tile = touchState.draggedTile
        local dragSpeed = 10 -- Higher = less lag, lower = more lag
        
        -- Update visual position to smoothly follow drag position
        tile.visualX = UI.Animation.smoothStep(tile.visualX, tile.dragX, dragSpeed, dt)
        tile.visualY = UI.Animation.smoothStep(tile.visualY, tile.dragY, dragSpeed, dt)
    end
end

function Touch.pressed(x, y, istouch, touchId)
    touchState.isPressed = true
    touchState.startX = x
    touchState.startY = y
    touchState.currentX = x
    touchState.currentY = y
    touchState.pressTime = 0
    touchState.touchId = touchId
    touchState.draggedTile = nil
    touchState.draggedFrom = nil

    -- Handle settings menu interactions (takes priority when open)
    if gameState.settingsMenuOpen then
        return
    end

    -- Check for settings button press during playing phase
    if gameState.gamePhase == "playing" and gameState.settingsButtonBounds then
        if isPointInRect(x, y, gameState.settingsButtonBounds) then
            gameState.settingsMenuOpen = true
            return
        end
    end

    if gameState.gamePhase == "map" then
        -- Initialize map dragging state
        if gameState.currentMap then
            touchState.mapDragStartCameraX = gameState.currentMap.cameraX
        end
        return
    end

    -- Prevent input during scoring sequence or when round is won
    if gameState.scoringSequence or gameState.gamePhase == "won" then
        return
    end
    
    local playButtonBounds = getPlayButtonBounds()
    if isPointInRect(x, y, playButtonBounds) then
        animateButtonPress("playButton")
        if #gameState.placedTiles > 0 then
            Touch.playPlacedTiles()
        end
        return
    end
    
    local discardButtonBounds = getDiscardButtonBounds()
    if isPointInRect(x, y, discardButtonBounds) then
        animateButtonPress("discardButton")
        Touch.discardSelectedTiles()
        return
    end
    
    if isInBoardArea(x, y) then
        local tile = Board.getTileAt(x, y)
        if tile then
            -- Prevent dragging anchor tiles
            if not tile.isAnchor then
                touchState.draggedTile = tile
                touchState.draggedFrom = "board"
            end
            return
        end
    end
    
    if isInHandArea(x, y) then
        local tile, index = Hand.getTileAt(gameState.hand, x, y)
        if tile then
            touchState.draggedTile = tile
            touchState.draggedFrom = "hand"
            touchState.draggedIndex = index
            
            -- Initialize drag state
            tile.isDragging = false -- Start as false, will become true when dragging
            tile.dragX = x
            tile.dragY = y
            tile.visualX = tile.x
            tile.visualY = tile.y
        end
    end
end

function Touch.released(x, y, istouch, touchId)
    if not touchState.isPressed then
        return
    end

    -- Handle settings menu interactions (takes priority when open)
    if gameState.settingsMenuOpen then
        -- Check for music toggle
        if gameState.settingsMusicToggleBounds and isPointInRect(x, y, gameState.settingsMusicToggleBounds) then
            UI.Audio.toggleMusic()
        -- Check for restart button
        elseif gameState.settingsRestartBounds and isPointInRect(x, y, gameState.settingsRestartBounds) then
            gameState.settingsMenuOpen = false
            initializeGame(false)  -- Restart from Round 1
            -- Generate new map for fresh start
            gameState.currentMap = Map.generateMap(gameState.screen.width, gameState.screen.height)
            gameState.gamePhase = "map"
        -- Check for close button
        elseif gameState.settingsCloseBounds and isPointInRect(x, y, gameState.settingsCloseBounds) then
            gameState.settingsMenuOpen = false
        end

        touchState.isPressed = false
        touchState.touchId = nil
        return
    end

    -- Handle victory screen - Continue to Map button
    if gameState.gamePhase == "won" then
        if gameState.continueToMapButton and isPointInRect(x, y, gameState.continueToMapButton) then
            -- Now increment round counter when player continues
            gameState.currentRound = gameState.currentRound + 1
            gameState.targetScore = gameState.baseTargetScore * (2 ^ (gameState.currentRound - 1))
            gameState.gamePhase = "map"
        end
        touchState.isPressed = false
        touchState.touchId = nil
        return
    end

    -- Handle loss screen - tap anywhere to restart
    if gameState.gamePhase == "lost" then
        -- Complete restart - back to round 1 with new map from node 0
        initializeGame(false)  -- false = not a new round, complete restart
        -- Generate a completely new map for fresh start
        gameState.currentMap = Map.generateMap(gameState.screen.width, gameState.screen.height)
        gameState.gamePhase = "map"  -- Start at map view, not directly in combat
        touchState.isPressed = false
        touchState.touchId = nil
        return
    end

    -- Handle map screen interactions
    if gameState.gamePhase == "map" then
        if gameState.currentMap then
            if Touch.isDragging() then
                -- Was dragging the map - no further action needed, camera was updated in moved()
                touchState.isDraggingMap = false
            else
                -- Was a tap - check for node selection
                local clickedNode = Map.getNodeAt(gameState.currentMap, x, y)
                if clickedNode and Map.isNodeAvailable(gameState.currentMap, clickedNode.id) then
                    -- Show confirmation dialog instead of immediately entering node
                    gameState.selectedNode = clickedNode
                    gameState.gamePhase = "node_confirmation"
                    
                    -- Trigger path preview animation
                    Map.updatePreviewPath(gameState.currentMap, clickedNode.id)
                end
            end
        end
        
        -- Clean up map drag state
        touchState.isDraggingMap = false
        if gameState.currentMap then
            gameState.currentMap.userDragging = false  -- Clear active dragging flag
            -- Keep manualCameraMode = true to preserve camera position
        end
        touchState.isPressed = false
        touchState.touchId = nil
        return
    elseif gameState.gamePhase == "node_confirmation" then
        -- Handle confirmation dialog interactions
        if gameState.confirmationButtons then
            local goButton = gameState.confirmationButtons.go
            local cancelButton = gameState.confirmationButtons.cancel
            local closeButton = gameState.confirmationButtons.close
            
            if isPointInRect(x, y, goButton) then
                -- GO button pressed - enter the selected node
                Touch.enterSelectedNode()
                touchState.isPressed = false
                touchState.touchId = nil
                return
            elseif isPointInRect(x, y, cancelButton) or isPointInRect(x, y, closeButton) then
                -- CANCEL/CLOSE button pressed - return to map
                gameState.selectedNode = nil
                gameState.gamePhase = "map"
                
                -- Clear path preview animation
                if gameState.currentMap then
                    Map.clearPreviewPath(gameState.currentMap)
                end
                
                touchState.isPressed = false
                touchState.touchId = nil
                return
            end
        end
        
        -- If touch is not on the confirmation panel, allow map interaction
        -- Check if touch is outside the panel area
        local screenWidth = gameState.screen.width
        local screenHeight = gameState.screen.height
        local panelWidth = UI.Layout.scale(350)
        local panelHeight = screenHeight * 0.8
        local panelX = screenWidth - panelWidth - UI.Layout.scale(20)
        local panelY = (screenHeight - panelHeight) / 2
        
        local isOutsidePanel = not (x >= panelX and x <= panelX + panelWidth and 
                                   y >= panelY and y <= panelY + panelHeight)
        
        if isOutsidePanel then
            -- Allow map interaction - check for new node selection or map dragging
            if gameState.currentMap then
                if Touch.isDragging() then
                    -- Was dragging the map - no further action needed, camera was updated in moved()
                    touchState.isDraggingMap = false
                else
                    -- Was a tap outside panel - check for node selection
                    local clickedNode = Map.getNodeAt(gameState.currentMap, x, y)
                    if clickedNode and Map.isNodeAvailable(gameState.currentMap, clickedNode.id) then
                        -- Select new node (replace current selection)
                        gameState.selectedNode = clickedNode
                        -- Stay in confirmation phase with new node
                        
                        -- Trigger path preview animation for new selection
                        Map.updatePreviewPath(gameState.currentMap, clickedNode.id)
                    end
                end
            end
        end
        
        -- Clean up map drag state
        touchState.isDraggingMap = false
        if gameState.currentMap then
            gameState.currentMap.userDragging = false
        end
        touchState.isPressed = false
        touchState.touchId = nil
        return
    elseif gameState.gamePhase == "tiles_menu" then
        -- Handle tile selection (multi-select with toggle)
        if gameState.tileOfferButtons then
            for i, button in ipairs(gameState.tileOfferButtons) do
                if isPointInRect(x, y, button) then
                    -- Toggle selection
                    if not gameState.selectedTilesToBuy then
                        gameState.selectedTilesToBuy = {}
                    end

                    local alreadySelected = false
                    local selectedIndex = nil
                    for idx, selectedI in ipairs(gameState.selectedTilesToBuy) do
                        if selectedI == i then
                            alreadySelected = true
                            selectedIndex = idx
                            break
                        end
                    end

                    if alreadySelected then
                        -- Deselect
                        table.remove(gameState.selectedTilesToBuy, selectedIndex)
                    else
                        -- Select
                        table.insert(gameState.selectedTilesToBuy, i)
                    end

                    touchState.isPressed = false
                    return
                end
            end
        end

        -- Handle confirm tile button (now handles multiple tiles)
        if gameState.confirmTileButton and isPointInRect(x, y, gameState.confirmTileButton) and gameState.confirmTileButton.enabled then
            Touch.confirmTileSelection()
            touchState.isPressed = false
            return
        end

        -- Handle return to map button (skip purchasing)
        if gameState.returnToMapButton and isPointInRect(x, y, gameState.returnToMapButton) then
            gameState.gamePhase = "map"
        end
        touchState.isPressed = false
    elseif gameState.gamePhase == "artifacts_menu" or gameState.gamePhase == "contracts_menu" then
        -- Handle menu screen interactions - only Return to Map button for now
        if gameState.returnToMapButton and isPointInRect(x, y, gameState.returnToMapButton) then
            gameState.gamePhase = "map"
        end
        touchState.isPressed = false
        touchState.touchId = nil
        return
    end
    
    if touchState.draggedTile and touchState.draggedFrom == "board" then
        if not Touch.isDragging() then
            -- Simple tap on board tile returns it to hand
            Touch.returnTileToHand(touchState.draggedTile)
        else
            -- Animate dragged board tile back to position
            Touch.animateTileToPosition(touchState.draggedTile, touchState.draggedTile.x, touchState.draggedTile.y)
        end
    elseif touchState.draggedTile and touchState.draggedFrom == "hand" then
        if Touch.isDragging() then
            if isInBoardArea(x, y) then
                local wasPlaced = Touch.placeTileOnBoard(touchState.draggedTile, touchState.draggedIndex, x, y)
                -- If placement failed, animate back to hand
                if not wasPlaced then
                    Touch.animateTileToHandPosition(touchState.draggedTile, touchState.draggedIndex)
                end
            else
                -- Animate back to hand position
                Touch.animateTileToHandPosition(touchState.draggedTile, touchState.draggedIndex)
            end
        else
            Hand.selectTile(gameState.hand, touchState.draggedTile)
            Touch.resetTileDragState(touchState.draggedTile)
        end
    end
    
    -- Clean up touch state but keep drag state until animations complete
    touchState.isPressed = false
    touchState.touchId = nil
    touchState.draggedTile = nil
    touchState.draggedFrom = nil
    touchState.draggedIndex = nil
    touchState.isDraggingMap = false
    -- Clear active dragging flag (but preserve manualCameraMode)
    if gameState.currentMap then
        gameState.currentMap.userDragging = false
        -- manualCameraMode stays unchanged - only cleared on node selection
    end
end

function Touch.moved(x, y, dx, dy, istouch, touchId)
    if touchState.isPressed and (touchId == nil or touchId == touchState.touchId) then
        touchState.currentX = x
        touchState.currentY = y
        
        -- Handle map screen dragging (works for both map phase and confirmation phase)
        if (gameState.gamePhase == "map" or gameState.gamePhase == "node_confirmation") and gameState.currentMap then
            if Touch.isDragging() then
                -- Start map dragging if not already
                if not touchState.isDraggingMap then
                    touchState.isDraggingMap = true
                    gameState.currentMap.userDragging = true  -- Tell renderer to stop auto camera updates
                    gameState.currentMap.manualCameraMode = true  -- Enable persistent manual camera mode
                    -- Stop any existing camera animation when user starts dragging
                    if gameState.currentMap.cameraAnimation then
                        UI.Animation.stopAll(gameState.currentMap)
                        gameState.currentMap.cameraAnimating = false
                        gameState.currentMap.cameraAnimation = nil
                    end
                end
                
                -- Update camera position based on drag
                local dragDistance = touchState.startX - x
                local newCameraX = touchState.mapDragStartCameraX + dragDistance
                
                -- Apply camera bounds checking
                local maxCameraX = math.max(0, gameState.currentMap.totalWidth - gameState.screen.width)
                gameState.currentMap.cameraX = math.max(0, math.min(maxCameraX, newCameraX))
                gameState.currentMap.cameraTargetX = gameState.currentMap.cameraX
            end
            return
        end
        
        -- Update drag position for dragged tile
        if touchState.draggedTile then
            touchState.draggedTile.dragX = x
            touchState.draggedTile.dragY = y
            
            -- Set dragging state when we exceed threshold
            if Touch.isDragging() and not touchState.draggedTile.isDragging then
                touchState.draggedTile.isDragging = true
                touchState.draggedTile.dragScale = 1.05 -- Slightly bigger when dragging
                touchState.draggedTile.dragOpacity = 0.9 -- Slightly transparent
            end
        end
    end
end

function Touch.placeTileOnBoard(tile, handIndex, dragX, dragY)
    if tile.placed then
        return false
    end

    -- Check max tiles limit from challenges (count non-anchor tiles only)
    local maxTiles = Challenges and Challenges.getMaxTilesLimit(gameState)
    if maxTiles then
        local nonAnchorCount = 0
        for _, placedTile in ipairs(gameState.placedTiles) do
            if not placedTile.isAnchor then
                nonAnchorCount = nonAnchorCount + 1
            end
        end

        if nonAnchorCount >= maxTiles then
            -- Show error message
            local centerX = gameState.screen.width / 2
            local centerY = gameState.screen.height / 2 - UI.Layout.scale(50)

            UI.Animation.createFloatingText("MAX " .. maxTiles .. " TILES!", centerX, centerY, {
                color = {0.9, 0.3, 0.3, 1},
                fontSize = "medium",
                duration = 1.5,
                riseDistance = 40,
                startScale = 0.8,
                endScale = 1.2,
                shake = 3,
                easing = "easeOutQuart"
            })

            return false
        end
    end

    -- Check if this tile is already placed on the board
    for _, placedTile in ipairs(gameState.placedTiles) do
        if placedTile.id == tile.id then
            return false  -- Prevent duplicate placement
        end
    end

    -- Find the actual current index of the tile in hand (in case hand was modified)
    local actualIndex = nil
    for i, handTile in ipairs(gameState.hand) do
        if handTile == tile then
            actualIndex = i
            break
        end
    end

    -- If tile is no longer in hand, abort
    if not actualIndex then
        return false
    end
    
    local clonedTile = Domino.clone(tile)
    clonedTile.placed = true
    
    -- Set orientation based on whether it's a double (visual only)
    if Domino.isDouble(clonedTile) then
        clonedTile.orientation = "vertical"
    else
        clonedTile.orientation = "horizontal"
    end
    
    local tilePlaced = false
    
    if #gameState.placedTiles == 0 then
        -- First tile goes in the middle
        table.insert(gameState.placedTiles, clonedTile)
        tilePlaced = true
    else
        -- Determine if placing left or right based on drag position
        local centerX, _ = UI.Layout.getBoardCenter()
        if dragX < centerX then
            -- Try to place on left side with auto-fitting
            if Touch.canFitLeft(clonedTile) then
                Touch.autoFitLeft(clonedTile)
                table.insert(gameState.placedTiles, 1, clonedTile)
                tilePlaced = true
            end
        else
            -- Try to place on right side with auto-fitting
            if Touch.canFitRight(clonedTile) then
                Touch.autoFitRight(clonedTile)
                table.insert(gameState.placedTiles, clonedTile)
                tilePlaced = true
            end
        end
    end
    
    -- Only remove from hand if tile was successfully placed
    if tilePlaced then
        -- Remove using the actual current index, not the potentially stale handIndex
        table.remove(gameState.hand, actualIndex)
        Board.arrangePlacedTiles()
        Hand.updatePositions(gameState.hand)

        -- Play tile placement sound
        UI.Audio.playTilePlaced()

        -- Find the placed tile and animate it to its final board position
        for _, placedTile in ipairs(gameState.placedTiles) do
            if placedTile.id == clonedTile.id then
                -- Start animation from current drag position to final board position
                placedTile.visualX = tile.dragX or tile.visualX
                placedTile.visualY = tile.dragY or tile.visualY
                placedTile.isDragging = false

                Touch.animateTileToPosition(placedTile, placedTile.x, placedTile.y)
                break
            end
        end
    end
    
    return tilePlaced
end

function Touch.canFitLeft(tile)
    if #gameState.placedTiles == 0 then
        return true
    end

    local leftmostTile = gameState.placedTiles[1]
    local leftValue = leftmostTile.left

    -- Check if tile can connect (either orientation)
    return tile.left == leftValue or tile.right == leftValue
end

function Touch.canFitRight(tile)
    if #gameState.placedTiles == 0 then
        return true
    end

    local rightmostTile = gameState.placedTiles[#gameState.placedTiles]
    local rightValue = rightmostTile.right

    -- Check if tile can connect (either orientation)
    return tile.left == rightValue or tile.right == rightValue
end

function Touch.autoFitLeft(tile)
    if #gameState.placedTiles == 0 then
        return
    end
    
    local leftmostTile = gameState.placedTiles[1]
    local leftValue = leftmostTile.left
    
    -- Auto-flip tile to make it connect properly
    -- When placing left, new tile's RIGHT side should match the left extreme's LEFT side
    if tile.left == leftValue then
        -- Tile needs to be flipped so its right side connects to left extreme
        Domino.flip(tile)
    end
    -- If tile.right == leftValue, no flip needed (correct orientation)
end

function Touch.autoFitRight(tile)
    if #gameState.placedTiles == 0 then
        return
    end
    
    local rightmostTile = gameState.placedTiles[#gameState.placedTiles]
    local rightValue = rightmostTile.right
    
    -- Auto-flip tile to make it connect properly
    -- When placing right, new tile's LEFT side should match the right extreme's RIGHT side
    if tile.right == rightValue then
        -- Tile needs to be flipped so its left side connects to right extreme
        Domino.flip(tile)
    end
    -- If tile.left == rightValue, no flip needed (correct orientation)
end

function Touch.playPlacedTiles()
    if #gameState.placedTiles == 0 then
        return
    end

    if Validation.canConnectTiles(gameState.placedTiles) then
        -- Get only the tiles placed this hand (exclude anchor tile)
        local tilesToScore = {}
        for _, tile in ipairs(gameState.placedTiles) do
            if not tile.isAnchor then
                table.insert(tilesToScore, tile)
            end
        end

        -- Make sure we have tiles to score
        if #tilesToScore > 0 then
            -- Start the animated scoring sequence with only the tiles placed this hand
            startScoringSequence(tilesToScore)
        end
    else
        -- Add error feedback for invalid plays
        local centerX = gameState.screen.width / 2
        local centerY = gameState.screen.height / 2 + UI.Layout.scale(50)
        
        UI.Animation.createFloatingText("INVALID PLAY", centerX, centerY, {
            color = {0.9, 0.3, 0.3, 1},
            fontSize = "medium",
            duration = 1.5,
            riseDistance = 40,
            startScale = 0.8,
            endScale = 1.2,
            shake = 3,
            easing = "easeOutQuart"
        })
        
        Touch.returnAllTilesToHand()
    end
end

function Touch.checkGameEnd()
    if gameState.score >= gameState.targetScore then
        -- Player won this round, show victory screen with continue button
        -- Don't increment round counter yet - wait for player to click continue

        -- Award coins based on hands remaining
        local handsLeft = gameState.maxHandsPerRound - gameState.handsPlayed
        local baseCoins = handsLeft * 2
        local bonusCoins = math.floor(gameState.startRoundCoins / 5)
        local totalCoins = baseCoins + bonusCoins

        if totalCoins > 0 then
            updateCoins(gameState.coins + totalCoins, {hasBonus = bonusCoins > 0})

            -- Show coin breakdown with floating text
            local centerX = gameState.screen.width / 2
            local centerY = gameState.screen.height / 2

            UI.Animation.createFloatingText(handsLeft .. " HANDS LEFT = " .. baseCoins .. " $",
                centerX, centerY + UI.Layout.scale(100), {
                color = {1, 0.9, 0.3, 1},
                fontSize = "medium",
                duration = 2.5,
                riseDistance = 60,
                startScale = 0.7,
                endScale = 1.2,
                easing = "easeOutBack"
            })

            if bonusCoins > 0 then
                UI.Animation.createFloatingText("BONUS: +" .. bonusCoins .. " $",
                    centerX, centerY + UI.Layout.scale(140), {
                    color = {1, 1, 0.5, 1},
                    fontSize = "medium",
                    duration = 2.5,
                    riseDistance = 60,
                    startScale = 0.7,
                    endScale = 1.2,
                    easing = "easeOutBack"
                })
            end
        end

        gameState.gamePhase = "won"

        -- If this was a boss round, generate a completely new map
        if gameState.isBossRound then
            gameState.currentMap = Map.generateMap(gameState.screen.width, gameState.screen.height)
            gameState.isBossRound = false
        else
            -- Regular combat node completion - return to existing map
            -- Generate a new map if one doesn't exist (shouldn't happen)
            if not gameState.currentMap then
                gameState.currentMap = Map.generateMap(gameState.screen.width, gameState.screen.height)
            end
        end
    elseif gameState.handsPlayed >= gameState.maxHandsPerRound then
        -- Player failed to reach target in 3 hands - they lose
        gameState.gamePhase = "lost"
    end
end

function Touch.returnAllTilesToHand()
    local tilesToReturn = {}
    for _, tile in ipairs(gameState.placedTiles) do
        local handTile = Domino.clone(tile)
        handTile.placed = false
        handTile.placedOrder = 0
        handTile.selected = false
        table.insert(tilesToReturn, handTile)
    end
    
    gameState.placedTiles = {}
    Hand.addTiles(gameState.hand, tilesToReturn)
end

function Touch.getDragDistance()
    if not touchState.isPressed then
        return 0
    end
    
    local dx = touchState.currentX - touchState.startX
    local dy = touchState.currentY - touchState.startY
    return math.sqrt(dx * dx + dy * dy)
end

function Touch.isDragging()
    return touchState.isPressed and Touch.getDragDistance() > getDragThreshold()
end

function Touch.isLongPress()
    return touchState.isPressed and touchState.pressTime > touchState.longPressTime
end

function Touch.returnTileToHand(tile)
    -- Find and remove the tile from placed tiles
    for i, placedTile in ipairs(gameState.placedTiles) do
        if placedTile == tile then
            table.remove(gameState.placedTiles, i)
            break
        end
    end

    -- Create a hand tile copy
    local handTile = Domino.clone(tile)
    handTile.placed = false
    handTile.orientation = "vertical"  -- Reset to hand orientation
    handTile.selected = false

    -- Use Hand module function to properly add the tile
    Hand.addTiles(gameState.hand, {handTile})

    -- Play tile return sound
    UI.Audio.playTileReturned()

    -- Automatically rearrange remaining tiles to close gaps
    Board.arrangePlacedTiles()
end

function Touch.discardSelectedTiles()
    if gameState.discardsUsed >= 2 or not Hand.hasSelectedTiles(gameState.hand) then
        return false
    end
    
    local selectedTiles = Hand.getSelectedTiles(gameState.hand)
    local discardedCount = #selectedTiles
    
    -- Remove selected tiles from hand using the existing Hand function
    Hand.removeSelectedTiles(gameState.hand)
    
    -- Draw new tiles to replace discarded ones
    Hand.refillHand(gameState.hand, gameState.deck, 7)
    
    gameState.discardsUsed = gameState.discardsUsed + 1
    
    return true
end

-- Animation helper functions
function Touch.animateTileToPosition(tile, targetX, targetY)
    if not tile then return end
    
    tile.isAnimating = true
    UI.Animation.animateTo(tile, {
        visualX = targetX,
        visualY = targetY,
        dragScale = 1.0,
        dragOpacity = 1.0
    }, 0.25, "easeOutBack", function()
        Touch.resetTileDragState(tile)
    end)
end

function Touch.animateTileToHandPosition(tile, handIndex)
    if not tile then return end
    
    -- Calculate target hand position
    local handSize = #gameState.hand
    local targetX, targetY = UI.Layout.getHandPosition(handIndex - 1, handSize)
    
    tile.isAnimating = true
    UI.Animation.animateTo(tile, {
        visualX = targetX,
        visualY = targetY,
        dragScale = 1.0,
        dragOpacity = 1.0
    }, 0.35, "easeOutBack", function()
        Touch.resetTileDragState(tile)
    end)
end

function Touch.resetTileDragState(tile)
    if not tile then return end
    
    tile.isDragging = false
    tile.isAnimating = false
    tile.dragScale = 1.0
    tile.dragOpacity = 1.0
    -- Keep visualX/Y as they are now the tile's display position
end

-- Trigger satisfying progression animation when moving to a new node
function Touch.triggerNodeProgressionAnimation(node)
    if not node or not node.tile then return end
    
    local centerX = gameState.screen.width / 2
    local centerY = gameState.screen.height / 2
    
    -- Create celebration text for node advancement
    local celebrationTexts = {
        "PATH CHOSEN!",
        "ADVANCING!",
        "GOOD CHOICE!",
        "ONWARD!"
    }
    local randomText = celebrationTexts[love.math.random(1, #celebrationTexts)]
    
    UI.Animation.createFloatingText(randomText, centerX, centerY - UI.Layout.scale(50), {
        color = {0.2, 1, 0.3, 1},
        fontSize = "large",
        duration = 2.0,
        riseDistance = 80,
        startScale = 0.3,
        endScale = 1.5,
        bounce = true,
        easing = "easeOutElastic"
    })
    
    -- Add score bonus animation for node progression
    local bonusPoints = node.nodeType == "final" and 100 or 25
    UI.Animation.createScorePopup(bonusPoints, centerX + UI.Layout.scale(100), centerY, true)
    
    -- Animate the node tile itself with a satisfying effect
    local tile = node.tile
    if tile then
        -- Store original scale
        tile.progressionScale = tile.progressionScale or 1.0
        
        -- Create a satisfying bounce effect
        UI.Animation.animateTo(tile, {progressionScale = 1.4}, 0.2, "easeOutBack", function()
            UI.Animation.animateTo(tile, {progressionScale = 1.1}, 0.3, "easeOutQuart", function()
                UI.Animation.animateTo(tile, {progressionScale = 1.0}, 0.4, "easeOutQuart")
            end)
        end)
    end
end

-- Trigger celebration when completing the entire map
function Touch.triggerMapCompletionCelebration()
    local centerX = gameState.screen.width / 2
    local centerY = gameState.screen.height / 2
    
    -- Main completion message
    UI.Animation.createFloatingText("MAP CONQUERED!", centerX, centerY - UI.Layout.scale(80), {
        color = {1, 0.8, 0.2, 1},
        fontSize = "title",
        duration = 3.0,
        riseDistance = 120,
        startScale = 0.2,
        endScale = 2.0,
        bounce = true,
        easing = "easeOutElastic"
    })
    
    -- Secondary message
    UI.Animation.createFloatingText("Advancing to Round " .. (gameState.currentRound + 1), 
        centerX, centerY, {
        color = {0.8, 0.9, 1, 1},
        fontSize = "large",
        duration = 2.5,
        riseDistance = 60,
        startScale = 0.5,
        endScale = 1.3,
        easing = "easeOutBack"
    })
    
    -- Big score bonus for map completion
    UI.Animation.createScorePopup(200, centerX, centerY + UI.Layout.scale(50), true)
end

-- Enter the selected node based on its type
function Touch.enterSelectedNode()
    if not gameState.selectedNode then
        return
    end
    
    local node = gameState.selectedNode
    local nodeType = node.nodeType
    
    -- Clear path preview animation when entering node
    if gameState.currentMap then
        Map.clearPreviewPath(gameState.currentMap)
        gameState.currentMap.manualCameraMode = false
    end
    
    -- Move to the selected node first
    local success = Map.moveToNode(gameState.currentMap, node.id)
    if not success then
        -- If move failed, return to map
        gameState.selectedNode = nil
        gameState.gamePhase = "map"
        return
    end
    
    -- Trigger progression animation
    Touch.triggerNodeProgressionAnimation(node)
    
    -- Route to appropriate screen based on node type
    if nodeType == "combat" or nodeType == "boss" then
        -- Mark if this is the boss node (map completion)
        if Map.isCompleted(gameState.currentMap) then
            gameState.isBossRound = true
            -- Trigger completion celebration
            Touch.triggerMapCompletionCelebration()
        else
            gameState.isBossRound = false
        end
        
        -- Reset combat state for fresh round (score=0, new deck/hand, reset counters)
        initializeCombatRound()
        
        -- All combat nodes (including boss) start combat round
        gameState.gamePhase = "playing"
    elseif nodeType == "tiles" then
        -- Generate tile offers when entering tiles menu
        gameState.offeredTiles = Domino.generateRandomTileOffers(gameState.tileCollection, 3)
        gameState.selectedTileOffer = nil
        gameState.selectedTilesToBuy = {}  -- Initialize empty selection for multi-purchase
        gameState.gamePhase = "tiles_menu"
    elseif nodeType == "artifacts" then
        gameState.gamePhase = "artifacts_menu"
    elseif nodeType == "contracts" then
        gameState.gamePhase = "contracts_menu"
    else
        -- Unknown node type, return to map
        gameState.gamePhase = "map"
    end
    
    -- Clear selected node
    gameState.selectedNode = nil
end

function Touch.confirmTileSelection()
    if not gameState.selectedTilesToBuy or #gameState.selectedTilesToBuy == 0 then
        return
    end

    if not gameState.offeredTiles then
        return
    end

    -- Calculate total cost
    local totalCost = #gameState.selectedTilesToBuy * 2

    -- Check if player can afford
    if gameState.coins < totalCost then
        -- Show error message
        local centerX = gameState.screen.width / 2
        local centerY = gameState.screen.height / 2

        UI.Animation.createFloatingText("NOT ENOUGH COINS!", centerX, centerY, {
            color = {0.9, 0.3, 0.3, 1},
            fontSize = "large",
            duration = 1.5,
            riseDistance = 40,
            startScale = 0.8,
            endScale = 1.2,
            shake = 3,
            easing = "easeOutQuart"
        })
        return
    end

    -- Deduct coins
    updateCoins(gameState.coins - totalCost, {hasBonus = false})

    -- Add all selected tiles to the player's collection and deck
    for _, tileIndex in ipairs(gameState.selectedTilesToBuy) do
        local selectedTile = gameState.offeredTiles[tileIndex]
        if selectedTile then
            -- Add to collection
            table.insert(gameState.tileCollection, Domino.clone(selectedTile))

            -- Add to current deck (for immediate use)
            table.insert(gameState.deck, Domino.clone(selectedTile))
        end
    end

    Domino.shuffleDeck(gameState.deck)

    -- Create a satisfying pickup animation
    local centerX = gameState.screen.width / 2
    local centerY = gameState.screen.height / 2

    local numTiles = #gameState.selectedTilesToBuy
    local message = numTiles == 1 and "TILE ACQUIRED!" or numTiles .. " TILES ACQUIRED!"

    UI.Animation.createFloatingText(message, centerX, centerY - UI.Layout.scale(50), {
        color = {0.2, 0.9, 0.3, 1},
        fontSize = "large",
        duration = 2.0,
        riseDistance = 100,
        startScale = 0.5,
        endScale = 1.5,
        bounce = true,
        easing = "easeOutBack"
    })

    -- Clear selection state and return to map
    gameState.offeredTiles = {}
    gameState.selectedTileOffer = nil
    gameState.selectedTilesToBuy = {}
    gameState.tileOfferButtons = {}
    gameState.confirmTileButton = nil
    gameState.gamePhase = "map"
end

return Touch