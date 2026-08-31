local component = require("component")
local shell = require("shell")
local _, ops = shell.parse(...)
local computer = require("computer")
local version = "0.3.0a"

-- ============================================================
-- CREDITS:
-- The code here was originally built following a tutorial by Javidx9 on youtube
-- "Code-It-Yourself! 3D Graphics Engine" -> https://youtu.be/ih20l3pJoeU
-- Since then, it has been heavily re-writtem and optimized for a low-memory lua environment.
-- ============================================================

-- Graphics Library
local gpu = require("chugraph")
gpu.SetMainGPU(component.gpu, "doubleHeight", true, true)

-- Input manager
local inputManager = require("chugkey")

-- ============================================================
-- RENDER CONFIGS
-- ============================================================

local doNormalFlatColoring = false
local doDepthBufferColoring = false
local doShadedColoring = false

local doModelRotate = false
local doModelRotateX = false
local doModelRotateZ = false
local doModelRotateY = false

local doDrawTextured = true
local doDrawFlatShaded = false              -- Not yet implemented
local doDrawWireframe = false
local doDepthBlending = false

local backgroundColor = 0x00DBFF            -- Color of the background in the scene
local depthFadeDist = 0.4                   -- Square depth value by this value when blending colors into the background
local bfcThreshold = 0.0                    -- Cull any face whos dot product against camera normal is above this
local bfcLazyThreshold = 0.8                -- Lazy backface culling threshold. Faces turned this far away should be lazy occluded
local lightDirection = {0.1, 0.1, -1}       -- [Sunlight-ish](0.3, 1, 0) | [Topdown-ish](0.1, 0.1, -1)
local shadeMaximum = 5 / 16                 -- Maximum darkness in the most shaded areas
local lightBias = 0.3                       -- Softens faces that are 90 degrees offset to light direction
local fNear = 0.25                          -- Near plane distance
local fFar = 1000                           -- Far plane distance
local fFov = 90                             -- Field of view

local modelFile = "teapot.obj"              -- Default loaded model, pretty much just for debugging

local function setArguments()
    -- load model from input filename
    if ops.model ~= nil then
        if string.find(ops.model, ".obj") == nil then
            modelFile = ops.model .. ".obj"
        else modelFile = ops.model end
    end
    if ops.back ~= nil then
        backgroundColor = ops.back + 0
    end
    if ops.n then doNormalFlatColoring = true end
    if ops.d then doDepthBufferColoring = true end
    if ops.s then doShadedColoring = true end
    if ops.b then doDepthBlending = true end
    if ops.f then doDrawFlatShaded = true end
    if ops.r then
        doModelRotate = true
        if ops.x then doModelRotateX = true
        elseif ops.z then doModelRotateZ = true
        elseif ops.y then doModelRotateY = true
        else
            doModelRotateX = true
            doModelRotateZ = true
            doModelRotateY = true
        end
    end
    if ops.w then doDrawWireframe = true end
end
setArguments()

-- ============================================================
-- LUA NONSENSE
-- ============================================================

local cos, sin, tan = math.cos, math.sin, math.tan
local min, max, abs = math.min, math.max, math.abs
local GetCPUTime = os.clock

local ClearScreen, UpdateScreen = gpu.ClearScreen, gpu.UpdateScreen
local SetText, SetPixel = gpu.SetText, gpu.SetPixel
local DrawTriangle, FillTriangle = gpu.DrawTriangle, gpu.FillTriangle
local GetGreyscaleColor, GetShadedColor, BlendColor = gpu.GetGreyscaleColor, gpu.GetShadedColor, gpu.BlendColor

local TInsert = table.insert; local TRemove = table.remove

-- ============================================================
-- TEXTURES & MODELS (Move to chugraph?)
-- ============================================================

-- Default cube, if no meshes are able to load
local defaultCubeOBJ = {
    "v -0.5 0.5 0.5", "v -0.5 -0.5 0.5", "v -0.5 0.5 -0.5", "v -0.5 -0.5 -0.5",
    "v 0.5 0.5 0.5", "v 0.5 -0.5 0.5", "v 0.5 0.5 -0.5", "v 0.5 -0.5 -0.5",
    "vt 0.875 0.5", "vt 0.625 0.75", "vt 0.625 0.5", "vt 0.375 1",
    "vt 0.375 0.75", "vt 0.625 0", "vt 0.375 0.25", "vt 0.375 0",
    "vt 0.375 0.5", "vt 0.125 0.75", "vt 0.125 0.5", "vt 0.625 0.25",
    "vt 0.875 0.75", "vt 0.625 1",
    "f 5/1 3/2 1/3", "f 3/2 8/4 4/5", "f 7/6 6/7 8/8", "f 2/9 8/10 6/11", "f 1/3 4/5 2/9", "f 5/12 2/9 6/7",
    "f 5/1 7/13 3/2", "f 3/2 7/14 8/4", "f 7/6 5/12 6/7", "f 2/9 4/5 8/10", "f 1/3 3/2 4/5", "f 5/12 1/3 2/9"
}

-- Default texture
local missingTex = {
    {0xFF00FF, 0x2D2D2D, 0xFF00FF, 0x2D2D2D},
    {0x2D2D2D, 0xFF00FF, 0x2D2D2D, 0xFF00FF},
    {0xFF00FF, 0x2D2D2D, 0xFF00FF, 0x2D2D2D},
    {0x2D2D2D, 0xFF00FF, 0x2D2D2D, 0xFF00FF},
}

-- TODO: This table should hold all loaded texture data associated with an .obj
-- Triangles should get a texture index, which will refer to an index in this table
local loadedTextures = {{name = "missingTex", w = #missingTex, h = #missingTex[1], tex = missingTex}}

-- ============================================================
-- .OBJ MESH LOADING
-- ============================================================

-- Triangle to store loaded mesh data
-- Vert indices are saved instead of vert values
-- TODO: Look into storing uv indices as well
-- VertIndex, Uvs, Texture, Color, Lighting
local function MemTriangle()
    return {{0, 0, 0}, {{0, 0, 1}, {0, 1, 1}, {1, 1, 1}}, 1, 1, 1}
end


local function fileExists(filename)
    local f = io.open(filename, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local vertPackS = "fffB"

-- For default cube mesh, this is probably stupid but I can't think of a clean way to merge this below
local function getMeshFromText(text)
    local tris, verts, uvs = {}, {}, {}
    for i = 1, #text do
        local line = text[i]
        local data = {}
        for item in line:gmatch("%S+") do
            TInsert(data, item)
        end
        if data == nil or data[1] == nil then goto continue end

        -- Vertex position
        if data[1] == "v" then
            TInsert(verts, string.pack(vertPackS, tonumber(data[2]), tonumber(data[3]), tonumber(data[4]), 1))

        -- UVs
        elseif data[1] == "vt" then
            TInsert(uvs, {tonumber(data[2]), tonumber(data[3])})

        -- Face data
        elseif data[1] == "f" then

            -- Check if face data packs other information inside
            local _, parts = data[2]:gsub("/", "")

            -- If more information than points given, then parse it
            if parts == 1 then

                local pointData = {}
                for j = 1, 3 do
                    for item in data[1 + j]:gmatch("%d+") do
                        TInsert(pointData, tonumber(item))
                    end
                end
                -- Create triangle, get its vertex indices and uv coordiantes
                local newTri = MemTriangle()
                newTri[1] =  {pointData[1], pointData[3], pointData[5]}
                newTri[2] = {{uvs[pointData[2]][1], uvs[pointData[2]][2], 1},
                             {uvs[pointData[4]][1], uvs[pointData[4]][2], 1},
                             {uvs[pointData[6]][1], uvs[pointData[6]][2], 1}}
                TInsert(tris, newTri)
            end
        end
        data = nil
        line = nil
        ::continue::
    end
    uvs = nil
    return tris, verts
end

-- Load .obj from file at filenam, parse vertex/face data and build a list of triangles from it 
local function getMeshFromFile(filename)
    local tris, verts, uvs = {}, {}, {}
    for line in io.lines(filename) do
        local data = {}
        for item in line:gmatch("%S+") do
            TInsert(data, item)
        end
        if data == nil or data[1] == nil then goto continue end

        -- Vertex position
        if data[1] == "v" then
            TInsert(verts, string.pack(vertPackS, tonumber(data[2]), tonumber(data[3]), tonumber(data[4]), 1))

        -- TODO: Vertex normals, could do shading eventually
        elseif data[1] == "vn" then
            -- Do nothing... for now....

        -- UVs
        elseif data[1] == "vt" then
            TInsert(uvs, {tonumber(data[2]), tonumber(data[3])})

        -- Face data
        elseif data[1] == "f" then

            -- Check if face data packs other information inside
            local _, parts = data[2]:gsub("/", "")

            -- If more information than points given, then parse it
            if parts == 1 then
                -- Vertex/UV

                local pointData = {}
                for i = 1, 3 do
                    for item in data[1 + i]:gmatch("%d+") do
                        TInsert(pointData, tonumber(item))
                    end
                end

                local newTri = MemTriangle()
                newTri[1] =  {pointData[1], pointData[3], pointData[5]}
                newTri[2] = {{uvs[pointData[2]][1], uvs[pointData[2]][2], 1},
                             {uvs[pointData[4]][1], uvs[pointData[4]][2], 1},
                             {uvs[pointData[6]][1], uvs[pointData[6]][2], 1}}
                TInsert(tris, newTri)

            elseif parts == 2 then
                -- Vertex/UV/Vertex-Normal

                local pointData = {}
                for i = 1, 3 do
                    for item in data[1 + i]:gmatch("%d+") do
                        TInsert(pointData, tonumber(item))
                    end
                end

                local newTri = MemTriangle()
                newTri[1] =  {pointData[1], pointData[4], pointData[7]}
                newTri[2] = {{uvs[pointData[2]][1], uvs[pointData[2]][2], 1},
                             {uvs[pointData[5]][1], uvs[pointData[5]][2], 1},
                             {uvs[pointData[8]][1], uvs[pointData[8]][2], 1}}
                TInsert(tris, newTri)

            -- Otherwise, just grab the verts
            else
                local newTri = MemTriangle()
                newTri[1] = {tonumber(data[2]), tonumber(data[3]), tonumber(data[4])}
                TInsert(tris, newTri)
            end
        end
        data, line = nil, nil
        ::continue::
    end
    uvs = nil
    return tris, verts
end

-- ============================================================
-- STRUCT FUNCTIONS
-- ============================================================

-- Add one vector to another
local function vectorAdd(v1, v2)
    return {v1[1] + v2[1], v1[2] + v2[2], v1[3] + v2[3], 1}
end

-- Subtract one vector from another
local function vectorSub(v1, v2)
    return {v1[1] - v2[1], v1[2] - v2[2], v1[3] - v2[3], 1}
end

-- Multiply vector by a value K
local function vectorMul(v1, k)
    return {v1[1] * k, v1[2] * k, v1[3] * k, 1}
end

-- Divide vector by a value K
local function vectorDiv(v1, k)
    return {v1[1] / k, v1[2] / k, v1[3] / k, 1}
end

-- Get dot product of two input vectors
local function vectorDotProduct(v1, v2)
    return v1[1] * v2[1] + v1[2] * v2[2] + v1[3] * v2[3]
end

-- Get length of vector
local function vectorLength(v)
    return vectorDotProduct(v, v) ^ -0.5
end

-- Normalize vector between -1 and 1
local function vectorNormalize(v)
    local l = vectorLength(v)
    return {v[1] * l, v[2] * l, v[3] * l, 1}
end

-- Get cross product of two input vectors
local function vectorCrossProduct(v1, v2)
    local v = {0, 0, 0, 1}
    v[1] = v1[2] * v2[3] - v1[3] * v2[2]
    v[2] = v1[3] * v2[1] - v1[1] * v2[3]
    v[3] = v1[1] * v2[2] - v1[2] * v2[1]
    return v
end

-- Get position at which vector intersects plane
local function vectorIntersectPlane(planeDP, ad, bd, lineStart, lineEnd)
    local t = (planeDP - ad) / (bd - ad)
    local lineStartToEnd = vectorSub(lineEnd, lineStart)
    local lineToIntersect = vectorMul(lineStartToEnd, t)

    lineStartToEnd = nil
    return vectorAdd(lineStart, lineToIntersect), t
end

local insidePi = {0, 0, 0}; local outsidePi = {0, 0, 0}
local insideTi = {0, 0, 0}; local outsideTi = {0, 0, 0}
local nInsideP = 0; local nOutsideP = 0

-- Test if triangle clips plane, return clipped triangles if so
local function triClipPlane(planeDP, planeN, inTri)

    local function dist(p)
        return planeN[1] * p[1] + planeN[2] * p[2] + planeN[3] * p[3] - planeDP
    end

    -- Calculate if point lies inside or outside of the clipping plane
    -- Save index of vertex in inTri instead of the entire vertex
    nInsideP, nOutsideP = 0, 0
    for i = 1, 3 do
        if dist(inTri[1][i]) >= 0 then
            nInsideP = nInsideP + 1
            insidePi[nInsideP] = i
            insideTi[nInsideP] = i
        else
            nOutsideP = nOutsideP + 1
            outsidePi[nOutsideP] = i
            outsideTi[nOutsideP] = i
        end
    end

    -- All points outside plane, should not be drawn
    if nInsideP == 0 then
        return 0

    -- All points within plane, requires no clipping
    elseif nInsideP == 3 then
        return 1, inTri

    -- Two points outside plane, return smaller tri
    elseif nInsideP == 1 and nOutsideP == 2 then

        -- Triangle needs to be clipped, two points lie outside
        local outTri1 = {{inTri[1][insidePi[1]], {0, 0, 0, 1}, {0, 0, 0, 1}}, {{inTri[2][insideTi[1]][1], inTri[2][insideTi[1]][2], inTri[2][insideTi[1]][3]}, {0, 0, 1}, {0, 0, 1}}}

        local t
        local lsDP = vectorDotProduct(inTri[1][insidePi[1]], planeN)
        outTri1[1][2], t = vectorIntersectPlane(
            planeDP,
            lsDP, vectorDotProduct(inTri[1][outsidePi[1]], planeN),
            inTri[1][insidePi[1]], inTri[1][outsidePi[1]]
        )
        outTri1[2][2][1] = t * (inTri[2][outsideTi[1]][1] - inTri[2][insideTi[1]][1]) + inTri[2][insideTi[1]][1]
        outTri1[2][2][2] = t * (inTri[2][outsideTi[1]][2] - inTri[2][insideTi[1]][2]) + inTri[2][insideTi[1]][2]
        outTri1[2][2][3] = t * (inTri[2][outsideTi[1]][3] - inTri[2][insideTi[1]][3]) + inTri[2][insideTi[1]][3]

        outTri1[1][3], t = vectorIntersectPlane(
            planeDP,
            lsDP, vectorDotProduct(inTri[1][outsidePi[2]], planeN),
            inTri[1][insidePi[1]], inTri[1][outsidePi[2]]
        )
        outTri1[2][3][1] = t * (inTri[2][outsideTi[2]][1] - inTri[2][insideTi[1]][1]) + inTri[2][insideTi[1]][1]
        outTri1[2][3][2] = t * (inTri[2][outsideTi[2]][2] - inTri[2][insideTi[1]][2]) + inTri[2][insideTi[1]][2]
        outTri1[2][3][3] = t * (inTri[2][outsideTi[2]][3] - inTri[2][insideTi[1]][3]) + inTri[2][insideTi[1]][3]

        planeDP, lsDP = nil, nil
        return 1, outTri1

    -- One point outside plane, return two smaller tris
    elseif nInsideP == 2 and nOutsideP == 1 then

        -- Triangle needs to be clipped, one pointing lies outside
        local outTri1 = {{inTri[1][insidePi[1]], inTri[1][insidePi[2]], {0, 0, 0, 1}}, {inTri[2][insideTi[1]], inTri[2][insideTi[2]], {0, 0, 1}}}
        local outTri2 = {{{0, 0, 0, 1}, {0, 0, 0, 1}, {0, 0, 0, 1}}, {{0, 0, 1}, {0, 0, 1}, {0, 0, 1}}}

        local t
        local leDP = vectorDotProduct(inTri[1][outsidePi[1]], planeN)
        outTri1[1][3], t = vectorIntersectPlane(
            planeDP,
            vectorDotProduct(inTri[1][insidePi[1]], planeN), leDP,
            inTri[1][insidePi[1]], inTri[1][outsidePi[1]]
        )
        outTri1[2][3][1] = t * (inTri[2][outsideTi[1]][1] - inTri[2][insideTi[1]][1]) + inTri[2][insideTi[1]][1]
        outTri1[2][3][2] = t * (inTri[2][outsideTi[1]][2] - inTri[2][insideTi[1]][2]) + inTri[2][insideTi[1]][2]
        outTri1[2][3][3] = t * (inTri[2][outsideTi[1]][3] - inTri[2][insideTi[1]][3]) + inTri[2][insideTi[1]][3]

        outTri2[1][1] = {inTri[1][insidePi[2]][1], inTri[1][insidePi[2]][2], inTri[1][insidePi[2]][3], inTri[1][insidePi[2]][4]}
        outTri2[2][1] = {inTri[2][insideTi[2]][1], inTri[2][insideTi[2]][2], inTri[2][insideTi[2]][3]}

        outTri2[1][2] = {outTri1[1][3][1], outTri1[1][3][2], outTri1[1][3][3], outTri1[1][3][4]}
        outTri2[2][2] = {outTri1[2][3][1], outTri1[2][3][2], outTri1[2][3][3]}
        outTri2[1][3], t = vectorIntersectPlane(
            planeDP,
            vectorDotProduct(inTri[1][insidePi[2]], planeN), leDP,
            inTri[1][insidePi[2]], inTri[1][outsidePi[1]]
        )
        outTri2[2][3][1] = t * (inTri[2][outsideTi[1]][1] - inTri[2][insideTi[2]][1]) + inTri[2][insideTi[2]][1]
        outTri2[2][3][2] = t * (inTri[2][outsideTi[1]][2] - inTri[2][insideTi[2]][2]) + inTri[2][insideTi[2]][2]
        outTri2[2][3][3] = t * (inTri[2][outsideTi[1]][3] - inTri[2][insideTi[2]][3]) + inTri[2][insideTi[2]][3]

        planeDP, leDP = nil, nil
        return 2, outTri1, outTri2
    end
    return 0
end

-- Return vector i multiplied by matrix m
local function matrixMultiplyVector(m, i)
    local v = {0, 0, 0, 0}
    v[1] = i[1] * m[1][1] + i[2] * m[2][1] + i[3] * m[3][1] + i[4] * m[4][1]
	v[2] = i[1] * m[1][2] + i[2] * m[2][2] + i[3] * m[3][2] + i[4] * m[4][2]
	v[3] = i[1] * m[1][3] + i[2] * m[2][3] + i[3] * m[3][3] + i[4] * m[4][3]
	v[4] = i[1] * m[1][4] + i[2] * m[2][4] + i[3] * m[3][4] + i[4] * m[4][4]
    return v
end

-- Set vector i multiplied by matrix m into reference table v
local function matrixMultiplyVectorR(v, m, i)
    v[1] = i[1] * m[1][1] + i[2] * m[2][1] + i[3] * m[3][1] + i[4] * m[4][1]
	v[2] = i[1] * m[1][2] + i[2] * m[2][2] + i[3] * m[3][2] + i[4] * m[4][2]
	v[3] = i[1] * m[1][3] + i[2] * m[2][3] + i[3] * m[3][3] + i[4] * m[4][3]
	v[4] = i[1] * m[1][4] + i[2] * m[2][4] + i[3] * m[3][4] + i[4] * m[4][4]
end

local function matrixMakeIdentity()
    return {{1, 0, 0, 0}, {0, 1, 0, 0,}, {0, 0, 1, 0}, {0, 0, 0, 1}}
end

-- Get rotation matrix at X angle angleRad
local function matrixMakeRotationX(angleRad)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = 1
	matrix[2][2] = cos(angleRad * 0.5)
	matrix[2][3] = sin(angleRad * 0.5)
	matrix[3][2] = -sin(angleRad * 0.5)
	matrix[3][3] = cos(angleRad * 0.5)
	matrix[4][4] = 1
    return matrix
end

-- Get rotation matrix at Y angle angleRad
local function matrixMakeRotationY(angleRad)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = cos(angleRad)
	matrix[1][3] = sin(angleRad)
	matrix[3][1] = -sin(angleRad)
	matrix[2][2] = 1
	matrix[3][3] = cos(angleRad)
	matrix[4][4] = 1
    return matrix
end

-- Get rotation matrix at Z angle angleRad
local function matrixMakeRotationZ(angleRad)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = cos(angleRad)
	matrix[1][2] = sin(angleRad)
	matrix[2][1] = -sin(angleRad)
	matrix[2][2] = cos(angleRad)
	matrix[3][3] = 1
	matrix[4][4] = 1
    return matrix
end

-- Get matrix translated to values x, y, z
local function matrixMakeTranslation(x, y, z)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = 1
    matrix[2][2] = 1
    matrix[3][3] = 1
    matrix[4][4] = 1
    matrix[4][1] = x
    matrix[4][2] = y
    matrix[4][3] = z
    return matrix
end

-- Create projection matrix from input FOV, aspect ratio, near and far distance
local function matrixMakeProjection(fFovDegrees, fAspectRatio, inFNear, inFFar)
    local fFovRad = 1 / tan(fFovDegrees * 0.5 / 180 * 3.14159)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = fAspectRatio * fFovRad
    matrix[2][2] = fFovRad
    matrix[3][3] = inFFar / (inFFar - inFNear)
	matrix[4][3] = (-inFFar * inFNear) / (inFFar - inFNear)
	matrix[3][4] = 1
	matrix[4][4] = 0
    return matrix
end

-- Multiply matrix m1 by matrix m2
local function matrixMultiplyMatrix(m1, m2)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    for c = 1, 4 do
        for r = 1, 4 do
            matrix[r][c] = m1[r][1] * m2[1][c] + m1[r][2] * m2[2][c] + m1[r][3] * m2[3][c] + m1[r][4] * m2[4][c]
        end
    end
    return matrix
end


local function matrixPointAt(pos, target, up)
    local newForward = vectorSub(target, pos)
    newForward = vectorNormalize(newForward)

    local a = vectorMul(newForward, vectorDotProduct(up, newForward))
    local newUp = vectorSub(up, a)
    newUp = vectorNormalize(newUp)

    local newRight = vectorCrossProduct(newUp, newForward)

    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = newRight[1];  	matrix[1][2] = newRight[2];	    matrix[1][3] = newRight[3];	    matrix[1][4] = 0
	matrix[2][1] = newUp[1];	    matrix[2][2] = newUp[2];	    matrix[2][3] = newUp[3];		matrix[2][4] = 0
	matrix[3][1] = newForward[1];	matrix[3][2] = newForward[2];	matrix[3][3] = newForward[3];	matrix[3][4] = 0
	matrix[4][1] = pos[1];			matrix[4][2] = pos[2];			matrix[4][3] = pos[3];			matrix[4][4] = 1
	return matrix;
end

-- Return inverse of matrix m
local function matrixQuickInverse(m)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
	matrix[1][1] = m[1][1]; matrix[1][2] = m[2][1]; matrix[1][3] = m[3][1]; matrix[1][4] = 0
	matrix[2][1] = m[1][2]; matrix[2][2] = m[2][2]; matrix[2][3] = m[3][2]; matrix[2][4] = 0
	matrix[3][1] = m[1][3]; matrix[3][2] = m[2][3]; matrix[3][3] = m[3][3]; matrix[3][4] = 0
	matrix[4][1] = -(m[4][1] * matrix[1][1] + m[4][2] * matrix[2][1] + m[4][3] * matrix[3][1])
	matrix[4][2] = -(m[4][1] * matrix[1][2] + m[4][2] * matrix[2][2] + m[4][3] * matrix[3][2])
	matrix[4][3] = -(m[4][1] * matrix[1][3] + m[4][2] * matrix[2][3] + m[4][3] * matrix[3][3])
	matrix[4][4] = 1
	return matrix;
end

-- ============================================================
-- RUNTIME
-- ============================================================

local loadedMesh = {}
local matProj, matRotY, matRotZ, matRotX
local vCamera, vLookDir = {0, 0, 0}, {0, 0, 0}
local fTheta, fYaw, fPitch = 0, 0, 0
local nLightDir

local screenWidth, screenHeight, halfWidth, halfHeight
local trisDrawnLast = 0

local elapsedTime = 0.1
local timeLast, nowTime = computer.uptime(), computer.uptime()

-- Near plane and viewspace offset
local nearPlane, nearNormal, vsOffset = {0, 0, fNear}, {0, 0, 1}, {1, 1, 0}

-- Reusable dot products
local vsLeftDP, vsRightDP, vsTopDP, vsBottomDP, nearDP

-- Get elapsed time per-frame for mesh rotation, if needed
local function updateElapsedTime()
    nowTime = computer.uptime()
    elapsedTime = nowTime - timeLast
    timeLast = nowTime
end

-- Load mesh from file and prepare it for rendering
local function createMesh()

    -- Precalculate some commonly used variables
    nLightDir = vectorNormalize(lightDirection)
    screenWidth = gpu.GetScreenWidth(); screenHeight = gpu.GetScreenHeight()
    halfWidth = 0.5 * screenWidth; halfHeight = 0.5 * screenHeight
    matProj = matrixMakeProjection(fFov, gpu.GetAspectRatio(), fNear, fFar)

    vsLeftDP = vectorDotProduct({1, 0, 0}, {1, 0, 0})
    vsRightDP = vectorDotProduct({screenWidth + 1, 0, 0}, {-1, 0, 0})
    vsTopDP = vectorDotProduct({0, 0, 0}, {0, 1, 0})
    vsBottomDP = vectorDotProduct({0, screenHeight, 0}, {0, -1, 0})
    nearDP = vectorDotProduct(nearPlane, nearNormal)

    -- Load model, or default to the cube
    -- Verts, Projected Verts, Viewspace Verts, Tris, Textures, Lazy BF Count Tricount, Vertcount
    loadedMesh = {vert = {}, pVert = {}, vsVert = {}, tris = {}, 0, lbfc = {}, triCount = 0, vertCount = 0}

    -- Get default-cube if that's what we really want
    if modelFile == "default-cube" then
        loadedMesh.tris, loadedMesh.vert = getMeshFromText(defaultCubeOBJ)

    -- Otherwise, get model from specified model file, if it exists
    else
        -- TODO: Look for texture with the same name as the loaded mesh and load it as well
        if fileExists(modelFile) then
            loadedMesh.tris, loadedMesh.vert = getMeshFromFile(modelFile)
        else
            modelFile = "default-cube-fallback"
            loadedMesh.tris, loadedMesh.vert = getMeshFromText(defaultCubeOBJ)
        end
    end

    -- Get tricount
    loadedMesh.triCount = #loadedMesh.tris
    loadedMesh.vertCount = #loadedMesh.vert

    -- We now have a list of verts and a list of tris with indeces pointing towards their 3 vertices
    -- Also, create a vertex list to contain projected and viewspace vertices
    for i = 1, loadedMesh.vertCount do
        loadedMesh.pVert[i] = {0, 0, 0, 1}
        loadedMesh.vsVert[i] = {0, 0, 0, 1}
    end

    -- Also build an array of values dictating whether or not a face gets lazy backface culled
    for i = 1, loadedMesh.triCount do
        loadedMesh.lbfc[i] = 0
    end
end

-- ============================================================
-- COLORS & TEXTURES TODO: Move all of this to chugraph
-- ============================================================

-- TODO: Move to chugraph
-- TODO: Optimize/fix oob errors
local depthBuffer = {}
local function resetDepthBuffer()
    depthBuffer = {}
end

-- TODO: Move to chugraph
-- TODO: Redo with barycentric coordinates?
local function getUVCoordinateColor(u, v)
    local uColor = ((u * 256) // 1) * 65536
    local vColor = ((v * 256) // 1) * 256
    return min(max(uColor + vColor, 0), 0xFFFFFF)
end

-- TODO: Move to chugraph
-- Get color from xyz value of face normal
local function getColorFromNormal(normal)
    -- Offset it for prettier colors
    local fixed = vectorAdd(vectorMul(normal, 0.5), {0.5, 0.5, 0.5})

    -- Inflate channel values back to 1-255, rounding to nearest available color index
    fixed[1] = (fixed[1] // 0.17) * 51
    fixed[2] = ((fixed[2] // 0.125) * 36.5) // 1
    fixed[3] = min((fixed[3] // 0.25) * 64, 255)

    -- Recompile into hex color
    return (fixed[1] << 16) + (fixed[2] << 8) + fixed[3]
end


-- TODO: Something is wrong here. FIX: u, v = v, u; u = 1 - u
-- TODO: Move to chugraph
local function uvSampleTexture(u, v, texIndex)
    local texWidth = loadedTextures[texIndex].w
    local texHeight = loadedTextures[texIndex].h
    u = ((u * texWidth) + 1) // 1
    v = ((v * texHeight) + 1) // 1
    u = min(max(u, 1), texWidth)
    v = min(max(v, 1), texHeight)
    if u > texWidth or u < 1 or v > texHeight or v < 1 then return 0xFFFFFF end
    return loadedTextures[texIndex].tex[v][u]
end

-- TODO: Move to chugraph
-- Draw triangle based on cl args
local function drawTexturedTriangle(x, y, tri, texU, texV, texW)
    -- TODO: More of these should be combinable
    -- Also should be re-ordered based on whatever is most commonly used? Or just rewritten more elegantly

    -- Greyscale depth buffer
    if doDepthBufferColoring then
        SetPixel(x, y, GetGreyscaleColor(texW))

    -- Blend texture color into the background
    elseif doDepthBlending then
        local sampleColor = uvSampleTexture(texU / texW, texV / texW, tri[3])
        if doShadedColoring then
            sampleColor = GetShadedColor(sampleColor, tri[5])
        end
        SetPixel(x, y, BlendColor(sampleColor, backgroundColor, texW ^ depthFadeDist))

    -- RGB according to surface normals
    elseif doNormalFlatColoring then
        SetPixel(x, y, tri[4])

    -- Shade texture based on angle to specified light source
    elseif doDrawFlatShaded then
        SetPixel(x, y, GetGreyscaleColor(tri[5]))

    -- Texture with shading based on per-triangle lighting
    elseif doShadedColoring then
        local sampleColor = uvSampleTexture(texU / texW, texV / texW, tri[3])
        SetPixel(x, y, GetShadedColor(sampleColor, tri[5]))

    -- Just texture
    else
        SetPixel(x, y, uvSampleTexture(texU / texW, texV / texW, tri[3]))
    end
end

-- ============================================================
-- PROJECTION & RENDERING
-- ============================================================

-- This seems kind of dumb
local texU, texV, texW
local daxStep, dbxStep
local du1Step, du2Step
local dv1Step, dv2Step
local dw1Step, dw2Step
local y1Delta, y2Delta, ax, bx
local texSu, texEu, texSv, texEv, texSw, texEw
local dx2, dx1, dy2, dy1, du2, du1, dv2, dv1, dw2, dw1

-- Draw projected triangle to the screen
local function texturedTriangle(p, u, tri)

    p[1][1] = p[1][1] // 1;  p[2][1] = p[2][1] // 1;  p[3][1] = p[3][1] // 1
    p[1][2] = p[1][2] // 1;  p[2][2] = p[2][2] // 1;  p[3][2] = p[3][2] // 1

    if (p[2][2] < p[1][2]) then
        p[1][1], p[2][1] = p[2][1], p[1][1]
        p[1][2], p[2][2] = p[2][2], p[1][2]
        u[1][1], u[2][1] = u[2][1], u[1][1]
        u[1][2], u[2][2] = u[2][2], u[1][2]
        u[1][3], u[2][3] = u[2][3], u[1][3]
    end
    if (p[3][2] < p[1][2]) then
        p[1][1], p[3][1] = p[3][1], p[1][1]
        p[1][2], p[3][2] = p[3][2], p[1][2]
        u[1][1], u[3][1] = u[3][1], u[1][1]
        u[1][2], u[3][2] = u[3][2], u[1][2]
        u[1][3], u[3][3] = u[3][3], u[1][3]
    end
    if (p[3][2] < p[2][2]) then
        p[2][1], p[3][1] = p[3][1], p[2][1]
        p[2][2], p[3][2] = p[3][2], p[2][2]
        u[2][1], u[3][1] = u[3][1], u[2][1]
        u[2][2], u[3][2] = u[3][2], u[2][2]
        u[2][3], u[3][3] = u[3][3], u[2][3]
    end

    dx1 = p[2][1] - p[1][1]
    dy1 = p[2][2] - p[1][2]
    du1 = u[2][1] - u[1][1]
    dv1 = u[2][2] - u[1][2]
    dw1 = u[2][3] - u[1][3]

    dx2 = p[3][1] - p[1][1]
    dy2 = p[3][2] - p[1][2]
    du2 = u[3][1] - u[1][1]
    dv2 = u[3][2] - u[1][2]
    dw2 = u[3][3] - u[1][3]

    texU, texV, texW = 0, 0, 0
    daxStep = 0; dbxStep = 0
    du1Step = 0; du2Step = 0
    dv1Step = 0; dv2Step = 0
    dw1Step = 0; dw2Step = 0

    daxStep = dx1 / abs(dy1)
    dbxStep = dx2 / abs(dy2)
    du1Step = du1 / abs(dy1)
    dv1Step = dv1 / abs(dy1)
    dw1Step = dw1 / abs(dy1)
    du2Step = du2 / abs(dy2)
    dv2Step = dv2 / abs(dy2)
    dw2Step = dw2 / abs(dy2)

    for i = p[1][2], p[2][2] do

        y1Delta = i - p[1][2]
        ax = (p[1][1] + y1Delta * daxStep) // 1
        bx = (p[1][1] + y1Delta * dbxStep) // 1

        -- Starting value
        texSu = u[1][1] + y1Delta * du1Step
        texSv = u[1][2] + y1Delta * dv1Step
        texSw = u[1][3] + y1Delta * dw1Step

        -- Ending value
        texEu = u[1][1] + y1Delta * du2Step
        texEv = u[1][2] + y1Delta * dv2Step
        texEw = u[1][3] + y1Delta * dw2Step

        if ax > bx then
            ax, bx = bx, ax
            texSu, texEu = texEu, texSu
            texSv, texEv = texEv, texSv
            texSw, texEw = texEw, texSw
        end

        texU = texSu
        texV = texSv
        texW = texSw

        local tStep = 1 / (bx - ax)
        local t = 0

        for j = ax, bx - 1 do

            texU = (1 - t) * texSu + t * texEu
            texV = (1 - t) * texSv + t * texEv
            texW = (1 - t) * texSw + t * texEw

            local depthIndex = (i * screenWidth) + j + 1
            if depthBuffer[depthIndex] == nil or texW > depthBuffer[depthIndex] then

                -- Draw pixel of triangle according to cl arg settings
                drawTexturedTriangle(j, i, tri, texU, texV, texW)
                depthBuffer[depthIndex] = texW
            end
            t = t + tStep
        end
    end

    dx1 = p[3][1] - p[2][1]
    dy1 = p[3][2] - p[2][2]
    du1 = u[3][1] - u[2][1]
    dv1 = u[3][2] - u[2][2]
    dw1 = u[3][3] - u[2][3]

    daxStep = dx1 / abs(dy1)
    dbxStep = dx2 / abs(dy2)
    du1Step = 0; dv1Step = 0
    du1Step = du1 / abs(dy1)
    dv1Step = dv1 / abs(dy1)
    dw1Step = dw1 / abs(dy1)

    for i = p[2][2], p[3][2] do

        y1Delta = i - p[1][2]
        y2Delta = i - p[2][2]
        ax = (p[2][1] + y2Delta * daxStep) // 1
        bx = (p[1][1] + y1Delta * dbxStep) // 1

        -- Starting value
        texSu = u[2][1] + y2Delta * du1Step
        texSv = u[2][2] + y2Delta * dv1Step
        texSw = u[2][3] + y2Delta * dw1Step

        -- Ending value
        texEu = u[1][1] + y1Delta * du2Step
        texEv = u[1][2] + y1Delta * dv2Step
        texEw = u[1][3] + y1Delta * dw2Step

        if ax > bx then
            ax, bx = bx, ax
            texSu, texEu = texEu, texSu
            texSv, texEv = texEv, texSv
            texSw, texEw = texEw, texSw
        end

        texU = texSu
        texV = texSv
        texW = texSw

        local tStep = 1 / (bx - ax)
        local t = 0

        for j = ax, bx - 1 do

            texU = (1 - t) * texSu + t * texEu
            texV = (1 - t) * texSv + t * texEv
            texW = (1 - t) * texSw + t * texEw

            local depthIndex = (i * screenWidth) + j + 1
            if depthBuffer[depthIndex] == nil or texW > depthBuffer[depthIndex] then

                -- Draw pixel of triangle according to cl arg settings
                drawTexturedTriangle(j, i, tri, texU, texV, texW)
                depthBuffer[depthIndex] = texW
            end
            t = t + tStep
        end
    end
end

local rasterizeStart; local rasterizeCumulative = 0
local clipTrisToRaster, testTri, vClipped = {}, {}, {}

-- Clip each triangle against each side of the viewport
-- After clipping, rasterize each triangle
local function viewportClipTriangle(trisToRaster)

    -- Check if any points are outside of screenspace
    local nNewTriangles = 1
    if trisToRaster[1][1][1][1] < 1 or trisToRaster[1][1][1][1] > screenWidth then goto clipTri end
    if trisToRaster[1][1][1][2] < 1 or trisToRaster[1][1][1][2] > screenHeight then goto clipTri end
    if trisToRaster[1][1][2][1] < 1 or trisToRaster[1][1][2][1] > screenWidth then goto clipTri end
    if trisToRaster[1][1][2][2] < 1 or trisToRaster[1][1][2][2] > screenHeight then goto clipTri end
    if trisToRaster[1][1][3][1] < 1 or trisToRaster[1][1][3][1] > screenWidth then goto clipTri end
    if trisToRaster[1][1][3][2] < 1 or trisToRaster[1][1][3][2] > screenHeight then goto clipTri end
    goto skipClip

    -- If points exist outside of screenspace, clip triangles against sides of viewport
    ::clipTri::
    for p = 1, 4 do

        local nTrisToAdd = 0
        while nNewTriangles > 0 do

            testTri = {
                trisToRaster[1][1],
                trisToRaster[1][2]
            }
            nNewTriangles = nNewTriangles - 1

            -- Check against each plane of the viewport
            -- Before sending to clip, make sure at least one point actually lies outside of that viewport plane
            vClipped = {}
            if p == 1 then
                -- Top
                if testTri[1][1][2] < 1 or testTri[1][2][2] < 1 or testTri[1][3][2] < 1 then
                    nTrisToAdd, vClipped[1], vClipped[2] = triClipPlane(vsTopDP, {0, 1, 0}, testTri)
                else
                    nTrisToAdd = -1
                    vClipped[1] = testTri
                end
			elseif p == 2 then
                -- Bottom
                if testTri[1][1][2] > screenHeight or testTri[1][2][2] > screenHeight or testTri[1][3][2] > screenHeight then
                    nTrisToAdd, vClipped[1], vClipped[2] = triClipPlane(vsBottomDP, {0, -1, 0}, testTri)
                else
                    nTrisToAdd = -1
                    vClipped[1] = testTri
                end
            elseif p == 3 then
                -- Left
                if testTri[1][1][1] < 1 or testTri[1][2][1] < 1 or testTri[1][3][1] < 1 then
                    nTrisToAdd, vClipped[1], vClipped[2] = triClipPlane(vsLeftDP, {1, 0, 0}, testTri)
                else
                    nTrisToAdd = -1
                    vClipped[1] = testTri
                end
			elseif p == 4 then
                -- Right
                if testTri[1][1][1] > screenWidth or testTri[1][2][1] > screenWidth or testTri[1][3][1] > screenWidth then
                    nTrisToAdd, vClipped[1], vClipped[2] = triClipPlane(vsRightDP, {-1, 0, 0}, testTri)
                else
                    nTrisToAdd = -1
                    vClipped[1] = testTri
                end
            end

            -- TODO: Do this more elegantly
            -- If no clipping occurred, just add triangle
            if nTrisToAdd == -1 then
                TInsert(trisToRaster, {vClipped[1][1], vClipped[1][2], trisToRaster[1][3], trisToRaster[1][4], trisToRaster[1][5]})
            -- If clipping occurred, add all new triangles
            else
                for w = 1, nTrisToAdd do
                    TInsert(trisToRaster, {vClipped[w][1], vClipped[w][2], trisToRaster[1][3], trisToRaster[1][4], trisToRaster[1][5]})
                end
            end

            TRemove(trisToRaster, 1)
            vClipped = nil
        end
        nNewTriangles = #trisToRaster
    end
    ::skipClip::

    -- Rasterize triangles based on what was specified in the cl args
    rasterizeStart = GetCPUTime() -- Timing
    for i = 1, nNewTriangles do

        -- Draw wireframe
        if doDrawWireframe then
            DrawTriangle(trisToRaster[i][1], 0xFFFFFF)

        -- Draw with texture
        elseif doDrawTextured then
            texturedTriangle(trisToRaster[i][1], trisToRaster[i][2], trisToRaster[i])
        end

        -- Debug
        trisDrawnLast = trisDrawnLast + 1
    end
    trisToRaster = nil
    rasterizeCumulative = rasterizeCumulative + (GetCPUTime() - rasterizeStart)
end

local projectionStart; local projectionCumulative = 0
local segmentTimeStart; local segmentCumulative = 0
local lazyCulledCount = 0
local pClipped, nPClipped = {}, 0
local normal, line1, line2 = {0, 0, 0}, {0, 0, 0}, {0, 0, 0}

-- Project verts, and then triangles from loaded mesh data
-- Each triangle gets sent into the rasterizer
local function rasterizeMesh()

    -- Rotate mesh if rotation enabled
    if doModelRotate then fTheta = fTheta + elapsedTime end
	matRotZ = matrixMakeRotationZ(doModelRotateZ and fTheta * 0.5 or 0)
	matRotX = matrixMakeRotationX(doModelRotateX and fTheta or 0)
    matRotY = matrixMakeRotationY(doModelRotateY and fTheta * 0.25 or 0)

    -- Amount to translate model in scene
    -- TODO: This should probably be packed into the loadedMesh table
    local matTrans = matrixMakeTranslation(0, 0, 7.5)

    -- Build mesh rotation matrix, handles if mesh is rotating
    local matWorld = matrixMakeIdentity()
    matWorld = matrixMultiplyMatrix(matRotZ, matRotX)
    matWorld = matrixMultiplyMatrix(matWorld, matRotY)
    matWorld = matrixMultiplyMatrix(matWorld, matTrans)

    -- Get camera rotation matrix from player control
    local vUp, vTarget = {0, 1, 0, 1}, {0, 0, 1, 1}
    local matCameraPitch = matrixMakeRotationX(fPitch)
    local matCameraYaw = matrixMakeRotationY(fYaw)
    local matCameraRot = matrixMultiplyMatrix(matCameraPitch, matCameraYaw)
    vLookDir = matrixMultiplyVector(matCameraRot, vTarget)
    vTarget = vectorAdd(vCamera, vLookDir)
    local matCamera = matrixPointAt(vCamera, vTarget, vUp) -- vCamera, vTarget, vUp
    local matView = matrixQuickInverse(matCamera)

    -- First, project vertices
    for i = 1, loadedMesh.vertCount do
        local unpackedV = table.pack(string.unpack(vertPackS, loadedMesh.vert[i]))
        matrixMultiplyVectorR(loadedMesh.pVert[i], matWorld, unpackedV)
        matrixMultiplyVectorR(loadedMesh.vsVert[i], matView, loadedMesh.pVert[i])
    end

    -- Then use projected vertices to construct and 
    for i = 1, loadedMesh.triCount do
        projectionStart = GetCPUTime()

        -- If triangle has a lazy culling index over 0, skip projection and decrement its index
        if loadedMesh.lbfc[i] > 0 then
            loadedMesh.lbfc[i] = loadedMesh.lbfc[i] - 1
            lazyCulledCount = lazyCulledCount + 1
            goto skipProj
        end

        -- Get face normal
        line1 = vectorSub(loadedMesh.pVert[loadedMesh.tris[i][1][2]], loadedMesh.pVert[loadedMesh.tris[i][1][1]])
        line2 = vectorSub(loadedMesh.pVert[loadedMesh.tris[i][1][3]], loadedMesh.pVert[loadedMesh.tris[i][1][1]])
        normal = vectorCrossProduct(line1, line2)
        normal = vectorNormalize(normal)

        -- Compare face normal against camera normal for backface culling
        local vCameraRay = vectorSub(loadedMesh.pVert[loadedMesh.tris[i][1][1]], vCamera)
        local normalToCamera = vectorDotProduct(normal, vCameraRay)

        projectionCumulative = projectionCumulative + (GetCPUTime() - projectionStart)
        if normalToCamera < bfcThreshold then
            projectionStart = GetCPUTime()

            -- Get amount of shade relative to light normal, and find normal color if needed
            local lightDp = max(min(lightBias + vectorDotProduct(nLightDir, normal), 1), shadeMaximum)
            if doNormalFlatColoring then loadedMesh.tris[i][4] = getColorFromNormal(normal) end

            -- Clip triangles against near plane
            -- TODO: Is there a quick check we can perform to skip this step for tris beyond the near plane?
            nPClipped, pClipped[1], pClipped[2] = triClipPlane(nearDP, nearNormal, {
                {loadedMesh.vsVert[loadedMesh.tris[i][1][1]],
                 loadedMesh.vsVert[loadedMesh.tris[i][1][2]],
                 loadedMesh.vsVert[loadedMesh.tris[i][1][3]]},
               {{loadedMesh.tris[i][2][1][1], loadedMesh.tris[i][2][1][2], loadedMesh.tris[i][2][1][3]},
                {loadedMesh.tris[i][2][2][1], loadedMesh.tris[i][2][2][2], loadedMesh.tris[i][2][2][3]},
                {loadedMesh.tris[i][2][3][1], loadedMesh.tris[i][2][3][2], loadedMesh.tris[i][2][3][3]}}
            })

            projectionCumulative = projectionCumulative + (GetCPUTime() - projectionStart) -- Timing point end
            for n = 1, nPClipped do
                projectionStart = GetCPUTime()

                -- Project points and uvs from 3D to 2D
                pClipped[n][1][1] = matrixMultiplyVector(matProj, pClipped[n][1][1])
                pClipped[n][1][2] = matrixMultiplyVector(matProj, pClipped[n][1][2])
                pClipped[n][1][3] = matrixMultiplyVector(matProj, pClipped[n][1][3])
                pClipped[n][2][1][1] = pClipped[n][2][1][1] / pClipped[n][1][1][4]
                pClipped[n][2][2][1] = pClipped[n][2][2][1] / pClipped[n][1][2][4]
                pClipped[n][2][3][1] = pClipped[n][2][3][1] / pClipped[n][1][3][4]
                pClipped[n][2][1][2] = pClipped[n][2][1][2] / pClipped[n][1][1][4]
                pClipped[n][2][2][2] = pClipped[n][2][2][2] / pClipped[n][1][2][4]
                pClipped[n][2][3][2] = pClipped[n][2][3][2] / pClipped[n][1][3][4]
                pClipped[n][2][1][3] = 1 / pClipped[n][1][1][4]
                pClipped[n][2][2][3] = 1 / pClipped[n][1][2][4]
                pClipped[n][2][3][3] = 1 / pClipped[n][1][3][4]

                -- Scale into view
                pClipped[n][1][1] = vectorDiv(pClipped[n][1][1], pClipped[n][1][1][4])
                pClipped[n][1][2] = vectorDiv(pClipped[n][1][2], pClipped[n][1][2][4])
                pClipped[n][1][3] = vectorDiv(pClipped[n][1][3], pClipped[n][1][3][4])

                -- Invert XY
                pClipped[n][1][1][1] = -pClipped[n][1][1][1]
				pClipped[n][1][2][1] = -pClipped[n][1][2][1]
				pClipped[n][1][3][1] = -pClipped[n][1][3][1]
				pClipped[n][1][1][2] = -pClipped[n][1][1][2]
				pClipped[n][1][2][2] = -pClipped[n][1][2][2]
				pClipped[n][1][3][2] = -pClipped[n][1][3][2]

                -- Offset verts into visible normalized space
                pClipped[n][1][1] = vectorAdd(pClipped[n][1][1], vsOffset)
                pClipped[n][1][2] = vectorAdd(pClipped[n][1][2], vsOffset)
                pClipped[n][1][3] = vectorAdd(pClipped[n][1][3], vsOffset)
                pClipped[n][1][1][1] = pClipped[n][1][1][1] * halfWidth
                pClipped[n][1][2][1] = pClipped[n][1][2][1] * halfWidth
                pClipped[n][1][3][1] = pClipped[n][1][3][1] * halfWidth
                pClipped[n][1][1][2] = pClipped[n][1][1][2] * halfHeight
                pClipped[n][1][2][2] = pClipped[n][1][2][2] * halfHeight
                pClipped[n][1][3][2] = pClipped[n][1][3][2] * halfHeight

                -- Copy texture over
                pClipped[n][3] = loadedMesh.tris[i][3]
                pClipped[n][4] = loadedMesh.tris[i][4]
                pClipped[n][5] = lightDp

                -- Send triangle to be viewport clipped and then rendered
                projectionCumulative = projectionCumulative + (GetCPUTime() - projectionStart)
                viewportClipTriangle({pClipped[n]})
                pClipped[n] = nil
            end
        elseif normalToCamera > bfcLazyThreshold then
            -- If tri is facing far enough away from the camera, halt projection for a frame or two
            loadedMesh.lbfc[i] = i % 2 + 1
        end
        ::skipProj::
    end
end

-- ============================================================
-- DEBUG
-- ============================================================

local debugCycles, maxDebugCycles = 1, 30
local projectionTimeTotal, rasterizeTimeTotal, segmentTimeTotal = 0, 0, 0
local debugFG, debugBG = 0xFFFFFF, 0x000000

-- Print debug stats to the screen
local function modelDebug()
    projectionTimeTotal = projectionTimeTotal + projectionCumulative
    rasterizeTimeTotal = rasterizeTimeTotal + rasterizeCumulative
    segmentTimeTotal = segmentTimeTotal + segmentCumulative
    local projAverage = projectionTimeTotal / debugCycles
    local rastAverage = rasterizeTimeTotal / debugCycles
    local segAverage = segmentTimeTotal / debugCycles

    SetText(1, 1, modelFile, debugFG, debugBG, false)
    SetText(1, 3, string.format("TRIS: %d - VERT: %d", loadedMesh.triCount, loadedMesh.vertCount), debugFG, debugBG, false)
    SetText(1, 5, string.format("DRAWN: %d", trisDrawnLast), debugFG, debugBG, false)
    SetText(1, 7, string.format("Proj: %0.1fms", (projAverage) * 1000), debugFG, debugBG, false)
    SetText(1, 9, string.format("Rast: %0.1fms", (rastAverage) * 1000), debugFG, debugBG, false)
    SetText(1, 11, string.format("LBFC: %d", lazyCulledCount), debugFG, debugBG, false)
    SetText(1, 13, string.format("SEG: %1.1fms", (segAverage) * 1000), debugFG, debugBG, false)

    segmentCumulative = 0
    projectionCumulative = 0
    rasterizeCumulative = 0
    lazyCulledCount = 0
    debugCycles = debugCycles + 1
    if debugCycles > maxDebugCycles then
        projectionTimeTotal = projAverage
        rasterizeTimeTotal = rastAverage
        segmentTimeTotal = segAverage
        debugCycles = 2
    end
end

-- ============================================================
-- CONTROL
-- ============================================================

local KEY_FORWARD, KEY_LEFT, KEY_BACKWARD, KEY_RIGHT = "W", "A", "S", "D"
local KEY_UP, KEY_DOWN, KEY_QUIT = "Z", "X", "Q"
local KEY_TURNLEFT, KEY_TURNRIGHT, KEY_TURNUP, KEY_TURNDOWN = "LEFT", "RIGHT", "UP", "DOWN"
local moveSpeed = 3
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
        local vRight = vectorMul({-vLookDir[3], 0, vLookDir[1]}, moveSpeed * elapsedTime)
        vCamera = vectorSub(vCamera, vRight)
    end
    if inputManager.isKeyDown(inputManager, KEY_RIGHT) then
        local vRight = vectorMul({-vLookDir[3], 0, vLookDir[1]}, moveSpeed * elapsedTime)
        vCamera = vectorAdd(vCamera, vRight)
    end
    if inputManager.isKeyDown(inputManager, KEY_FORWARD) then
        local vForward = vectorMul(vLookDir, moveSpeed * elapsedTime)
        vCamera = vectorAdd(vCamera, vForward)
    end
    if inputManager.isKeyDown(inputManager, KEY_BACKWARD) then
        local vForward = vectorMul(vLookDir, moveSpeed * elapsedTime)
        vCamera = vectorSub(vCamera, vForward)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNLEFT) then
        fYaw = fYaw - (2 * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNRIGHT) then
        fYaw = fYaw + (2 * elapsedTime)
    end
    -- TODO: This changes the speed of translation
    if inputManager.isKeyDown(inputManager, KEY_TURNUP) then
        fPitch = fPitch - (2 * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNDOWN) then
        fPitch = fPitch + (2 * elapsedTime)
    end
end

-- ============================================================
-- RUN THE DAMN THING
-- ============================================================

local function renderTriangles()
    ClearScreen()
    resetDepthBuffer()
    rasterizeMesh()
end

local function main()
    ClearScreen()
    createMesh()
    gpu.SetSceneBackground(backgroundColor)
    while true do

        -- update elapsed time
        updateElapsedTime()

        -- Take player's input controls
        inputManager.updateKeypress(inputManager)
        local exit = applyInputControls()
        if exit then
            gpu.ResetToCommandLine()
            package.loaded["chugraph"] = nil
            package.loaded["chugkey"] = nil
            break
        end

        -- Clear screen and draw projected triangles
        renderTriangles()

        -- Draw debug, render screen
        modelDebug()
        UpdateScreen()

        -- Reset debug values
        trisDrawnLast = 0
    end
end
main()

print("Projected with Chug3D " .. version)