-- config
local opts = {
}
(require 'mp.options').read_options(opts,"annotation")

local mpmsg = require 'mp.msg'
local dump = require 'dump'
local debug = require 'debug'

local msg = {}

local function wrap_message(...)
    local info = debug.getinfo(3)
    return '[' .. info.short_src .. ']:' .. info.currentline , ...
end

function msg.fatal(...)
    mpmsg.fatal(wrap_message(...))
end

function msg.error(...)
    mpmsg.error(wrap_message(...))
end

function msg.warn(...)
    mpmsg.warn(wrap_message(...))
end

function msg.info(...)
    mpmsg.info(wrap_message(...))
end

function msg.verbose(...)
    mpmsg.verbose(wrap_message(...))
end

function msg.debug(...)
    mpmsg.debug(wrap_message(...))
end

function msg.trace(...)
    mpmsg.trace(wrap_message(...))
end



return msg
