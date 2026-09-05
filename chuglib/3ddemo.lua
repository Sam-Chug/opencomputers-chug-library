local component = require("component")
local shell = require("shell")
local _, ops = shell.parse(...)
local computer = require("computer")

-- Graphics Library
local gpu = require("chugraph")
gpu.SetMainGPU(component.gpu, "doubleHeight", false, true)

-- 3D Library
local chug3d = require("chug3d")
chug3d.SetMainGPU(gpu)

local inputManager = require("chugkey")

local KEY_FORWARD, KEY_LEFT, KEY_BACKWARD, KEY_RIGHT = "W", "A", "S", "D"
local KEY_UP, KEY_DOWN, KEY_QUIT, KEY_WIREFRAME = "Z", "X", "Q", "P"
local KEY_TURNLEFT, KEY_TURNRIGHT, KEY_TURNUP, KEY_TURNDOWN = "LEFT", "RIGHT", "UP", "DOWN"
local moveSpeed, keyCooldown = 3, 0
local function applyInputControls()

    -- Apply values based on keypress
    if inputManager.isKeyDown(inputManager, KEY_QUIT) then
        return true
    end
    if inputManager.isKeyDown(inputManager, KEY_UP) then
        vCamera[2] = vCamera[2] + (moveSpeed * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_DOWN) then
        vCamera[2] = vCamera[2] - (moveSpeed * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_LEFT) then
        -- right: x = -z and z = x
        local vRight = vMul({-vLookDir[3], 0, vLookDir[1]}, moveSpeed * elapsedTime)
        vCamera = vSub(vCamera, vRight)
    end
    if inputManager.isKeyDown(inputManager, KEY_RIGHT) then
        local vRight = vMul({-vLookDir[3], 0, vLookDir[1]}, moveSpeed * elapsedTime)
        vCamera = vAdd(vCamera, vRight)
    end
    if inputManager.isKeyDown(inputManager, KEY_FORWARD) then
        local vForward = vMul(vLookDir, moveSpeed * elapsedTime)
        vCamera = vAdd(vCamera, vForward)
    end
    if inputManager.isKeyDown(inputManager, KEY_BACKWARD) then
        local vForward = vMul(vLookDir, moveSpeed * elapsedTime)
        vCamera = vSub(vCamera, vForward)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNLEFT) then
        fYaw = fYaw - (2 * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNRIGHT) then
        fYaw = fYaw + (2 * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNUP) then
        fPitch = fPitch - (2 * elapsedTime) -- TODO: These change the speed of translation
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNDOWN) then
        fPitch = fPitch + (2 * elapsedTime)
    end
    if keyCooldown == 0 then
        if inputManager.isKeyDown(inputManager, KEY_WIREFRAME) then
            ChangeRenderSetting("draw-wireframe", not drawWireFrame)
            keyCooldown = 10
        end
    end
    keyCooldown = max(keyCooldown - 1, 0)
end

local function main()

    gpu.ClearScreen()
    gpu.SetSceneBackground(0x00DBFF)

    chug3d.LoadSceneMeshes({"homer.obj", "teapot.obj"})
    chug3d.PlaceMeshInScene(1, nil, {0, 0, 7.5}, {0, 0, 0})
    chug3d.PlaceMeshInScene(2, nil, {7.5, 0, 7.5}, {0, 0, 0})
    chug3d.RebuildRenderPipeline()

    -- Force garbage collection before starting
    for i = 1, 10 do os.sleep(0) end

    while true do

        local exit = applyInputControls()
        if exit then
            gpu.ResetToCommandLine()
            package.loaded["chugraph"] = nil
            package.loaded["chugkey"] = nil
            package.loaded["chugbmp"] = nil
            break
        end

        gpu.ClearScreen()

        gpu.SetText(5, 5, "Demo Test", 0xFFFFFF, 0x000000, false)
        chug3d.RenderScene()
        -- modelDebug()
        gpu.UpdateScreen()

        -- Take player's input controls (yielding)
        inputManager.updateKeypress(inputManager)
    end
end
main()