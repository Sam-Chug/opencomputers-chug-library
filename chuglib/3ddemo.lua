local component = require("component")
local shell = require("shell")
local _, ops = shell.parse(...)
local computer = require("computer")

-- Graphics Library
local gpu = require("chugraph")
gpu.SetMainGPU(component.gpu, "doubleHeight", true, true)

-- 3D Library
local 