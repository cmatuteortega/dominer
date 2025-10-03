UI = UI or {}
UI.Layout = {}

local layout = {
    padding = 20,
    handY = 0,
    boardY = 0,
    boardCenterX = 0,
    boardCenterY = 0,
    tileSize = { width = 60, height = 30 },
    isCalculated = false
}

function UI.Layout.begin()
    if not layout.isCalculated then
        UI.Layout.recalculate()
    end
end

function UI.Layout.recalculate()
    local screen = gameState.screen
    local scale = screen.scale
    
    -- Responsive scaling based on screen dimensions and device type
    local isPortrait = screen.height > screen.width
    local isMobile = screen.width < 1024 or love.system.getOS() == "Android" or love.system.getOS() == "iOS"
    
    -- Adaptive sprite scaling
    local minScale = math.min(screen.width / 800, screen.height / 600)
    local spriteScale = math.max(minScale * 1.5, 0.8) -- Minimum scale for mobile readability
    
    -- Responsive tile sizing
    layout.tileSize.width = 80 * spriteScale
    layout.tileSize.height = 40 * spriteScale
    
    -- Adaptive padding and spacing for mobile
    layout.padding = isMobile and math.max(10 * scale, 20) or 20 * scale
    
    -- Removed hand tile spacing since tiles are now displayed without gaps
    
    -- Mobile-optimized UI areas  
    local uiSpacing = isMobile and math.max(15 * scale, 10) or 10 * scale
    
    -- Calculate button height for layout (using our new smaller buttons)
    local buttonHeight = isMobile and math.max(40 * scale, 35) or 35 * scale
    
    layout.handY = screen.height - layout.tileSize.height - layout.padding - buttonHeight - (uiSpacing * 2)
    layout.boardY = layout.padding
    layout.boardCenterX = screen.width / 2
    layout.boardCenterY = (layout.boardY + layout.handY - buttonHeight - uiSpacing) / 2 + (30 * scale)
    
    layout.isCalculated = true
end

function UI.Layout.finish()
end

function UI.Layout.getHandPosition(index, totalTiles)
    -- Calculate actual sprite dimensions as they appear on screen
    local screen = gameState.screen
    
    -- Use the same sprite scaling logic as in UI.Renderer.drawDomino
    local minScale = math.min(screen.width / 800, screen.height / 600)
    local spriteScale = math.max(minScale * 2.0, 1.0)
    
    -- Get a sample sprite to determine actual rendered width
    -- Use the 0-0 domino as our reference sprite
    local sampleSpriteData = dominoSprites and dominoSprites["00"]
    local spriteWidth
    
    if sampleSpriteData and sampleSpriteData.sprite then
        -- Calculate actual rendered width using the same scaling as renderer
        spriteWidth = sampleSpriteData.sprite:getWidth() * spriteScale
    else
        -- Fallback to layout tile size if sprite not available
        spriteWidth = layout.tileSize.width
    end
    
    -- Calculate total width of all tiles with no gaps
    local totalHandWidth = totalTiles * spriteWidth
    
    -- Center the entire hand block on screen
    local startX = (screen.width - totalHandWidth) / 2
    
    -- Position each tile - sprites are drawn centered, so we need center positions
    -- First tile center is at startX + spriteWidth/2
    -- Each subsequent tile is spriteWidth apart
    local x = startX + (spriteWidth / 2) + (index * spriteWidth)
    
    return x, layout.handY
end

function UI.Layout.getBoardCenter()
    return layout.boardCenterX, layout.boardCenterY
end

function UI.Layout.getTileSize()
    return layout.tileSize.width, layout.tileSize.height
end

function UI.Layout.getHandArea()
    return {
        x = 0,
        y = layout.handY - layout.padding,
        width = gameState.screen.width,
        height = layout.tileSize.height + layout.padding * 2
    }
end

function UI.Layout.getBoardArea()
    return {
        x = 0,
        y = layout.boardY,
        width = gameState.screen.width,
        height = layout.handY - layout.boardY - layout.padding
    }
end

function UI.Layout.scale(value)
    return value * gameState.screen.scale
end

function UI.Layout.getButtonSize()
    local scale = gameState.screen.scale
    local isMobile = gameState.screen.width < 1024 or love.system.getOS() == "Android" or love.system.getOS() == "iOS"
    
    -- Smaller button sizes for under-hand positioning
    local width = isMobile and math.max(100 * scale, 90) or 90 * scale
    local height = isMobile and math.max(40 * scale, 35) or 35 * scale
    
    return width, height
end

function UI.Layout.isMobile()
    return gameState.screen.width < 1024 or love.system.getOS() == "Android" or love.system.getOS() == "iOS"
end

function UI.Layout.isPortrait()
    return gameState.screen.height > gameState.screen.width
end

function UI.Layout.getPlayButtonPosition()
    local buttonWidth, buttonHeight = UI.Layout.getButtonSize()
    local handArea = UI.Layout.getHandArea()
    
    -- Position buttons under the hand area, side by side
    local totalButtonWidth = buttonWidth * 2 + UI.Layout.scale(10) -- Two buttons plus spacing
    local startX = (gameState.screen.width - totalButtonWidth) / 2
    
    local x = startX + buttonWidth + UI.Layout.scale(10) -- Right button (play)
    local y = handArea.y + handArea.height + UI.Layout.scale(10)
    
    return x, y
end

function UI.Layout.getDiscardButtonPosition()
    local buttonWidth, buttonHeight = UI.Layout.getButtonSize()
    local handArea = UI.Layout.getHandArea()

    -- Position buttons under the hand area, side by side
    local totalButtonWidth = buttonWidth * 2 + UI.Layout.scale(10) -- Two buttons plus spacing
    local startX = (gameState.screen.width - totalButtonWidth) / 2

    local x = startX -- Left button (discard)
    local y = handArea.y + handArea.height + UI.Layout.scale(10)

    return x, y
end

function UI.Layout.getSettingsButtonPosition()
    local buttonSize = UI.Layout.scale(40)
    local padding = UI.Layout.scale(20)

    local x = padding
    local y = gameState.screen.height - buttonSize - padding

    return x, y, buttonSize
end

function UI.Layout.getCoinDisplayPosition()
    local padding = UI.Layout.scale(20)
    local settingsX, settingsY, settingsSize = UI.Layout.getSettingsButtonPosition()

    -- Position for coin counter text
    local textX = settingsX + settingsSize / 2 - UI.Layout.scale(20)  -- Move to the left
    local textY = settingsY - UI.Layout.scale(60)

    -- Position for coin stack (separate from text)
    local stackX = settingsX + settingsSize / 2 + UI.Layout.scale(60)
    local stackY = settingsY - UI.Layout.scale(60)

    return textX, textY, stackX, stackY
end

return UI.Layout