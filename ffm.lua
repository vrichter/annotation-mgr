local fformation = require("libfformation-gco_lua")
local dump = require 'dump'
local msg = require 'msg'

local Ffm = {}
function Ffm:new(alg, mdl, stride)
    o = {}
    setmetatable(o, self)
    self.__index = self
    self.alg = alg
    self.mdl = mdl
    self.stride = stride
    self:init_impl()
    return o
end
function Ffm:detect(table)
    return self.impl:detect(table)
end
function Ffm:init_impl()
    local settings = self.alg.."@mdl="..self.mdl.."@stride="..self.stride
    msg.info("setting ffm to: "..settings)
    self.impl = GroupDetector(settings)
end
function Ffm:set_alg(alg)
    self.alg = alg
    self:init_impl()
end
function Ffm:set_stride(stride)
    self.stride = stride
    self:init_impl()
end
function Ffm:set_mdl(mdl)
    self.mdl = mdl
    self:init_impl()
end
function Ffm:inc_alg()
    local algs = self.impl:list_alg({})
    local current = 1
    for k,v in pairs(algs) do
        if v == self.alg then
            current = k
        end
    end
    self.alg = algs[current+1] or algs[1]
    self:init_impl()      
end
function Ffm:inc_stride()
    self.stride = self.stride*1.1
    self:init_impl()
end
function Ffm:dec_stride()
    self.stride = self.stride*0.9
    self:init_impl()
end
function Ffm:inc_mdl()
    self.mdl = self.mdl*1.1
    self:init_impl()
end
function Ffm:dec_mdl()
    self.mdl = self.mdl*0.9
    self:init_impl()
end
return Ffm