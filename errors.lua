
--Structured exceptions for Lua.
--Written by Cosmin Apreutesei. Public Domain.

--prototype-based dynamic inheritance with __call constructor (from glue).
local function object(super, o)
	o = o or {}
	o.__index = super
	o.__call = super and super.__call
	o.__tostring = super and super.__tostring
	return setmetatable(o, o)
end

local lua_error = error

local classes = {} --{name -> class}
local class_sets = {} --{'name1 name2 ...' -> {class->true}}
local error --base error class, defined below.

local function errortype(classname, super)
	local class = classname and classes[classname]
	if not class then
		super = type(super) == 'string' and assert(classes[super]) or super or error
		class = object(super, {classname = classname, iserror = true})
		if classname then
			classes[classname] = class
			class_sets = {}
		end
	end
	return class
end

error = errortype'error'
error.init = function() end

local function iserror(e)
	return type(e) == 'table' and e.iserror
end

local function newerror(arg, ...)
	if type(arg) == 'string' then
		local class = classes[arg] or errortype(arg)
		return class(...)
	end
	return arg
end

local function class_table(s)
	if type(s) == 'string' then
		local t = class_sets[s]
		if not t then
			t = {}
			class_sets[s] = t
			for s in s:gmatch'[^%s,]+' do
				local class = classes[s]
				while class do
					t[class] = true
					class = class.__index
				end
			end
		end
		return t
	else
		assert(type(s) == 'table')
		return s --if given as table, must contain superclasses too!
	end
end

local function iserrorof(e, classes)
	if not iserror(e) then return false end
	if not classes then return true end
	return class_table(classes)[e.__index] or false
end

function error:__call(arg1, ...)
	local e
	if type(arg1) == 'table' then
		e = object(self, arg1)
		e.message = e.message or (... and string.format(...) or nil)
	else
		e = object(self, {message = arg1 and string.format(arg1, ...) or nil})
	end
	e:init()
	return e
end

function error:__tostring()
	local s = self.traceback or self.message or self.classname
	if self.errorcode then
		s = s .. ' ['..self.errorcode..']'
	end
	return s
end

local function raise(...)
	lua_error((newerror(...)))
end

local function pass(classes, ok, ...)
	if ok then return true, ... end
	local e = ...
	if not classes then --catch-all
		return false, e
	elseif iserrorof(e, classes) then
		return false, e
	end
	lua_error(e)
end
local function onerror(e)
	if iserror(e) then
		if e.addtraceback then
			e.traceback = debug.traceback(e.message, 2)
		end
	else
		return debug.traceback(e, 2)
	end
	return e
end
local function zpcall(f, ...)
	return xpcall(f, onerror, ...)
end
local function catch(classes, f, ...)
	return pass(classes, zpcall(f, ...))
end

local function check(class, v, ...)
	if v then return v, ... end
	raise(class, ...)
end

local function pass(ok, ...)
	if ok then return ... end
	return nil, ...
end
local function protect(classes, f)
	return function(...)
		return pass(catch(classes, f, ...))
	end
end

local function wrap(f,...)
	local fint, errt = {}, {}
	local function finally(f) fint[#fint+1] = f end
	local function onerror(f) errt[#errt+1] = f end
	local function err(e)
		for i=#errt,1,-1 do errt[i](e) end
		return debug.traceback(e, 2)
	end
	local function pass(ok, ...)
		for i=#fint,1,-1 do fint[i]() end
		if not ok then
			error((...), 2)
		end
		return ...
	end
	return function(...)
		return pass(zpcall(f, err, finally, onerror, ...))
	end
end

local M = {
	error = error,
	errortype = errortype,
	new = newerror,
	is = iserrorof,
	raise = raise,
	catch = catch,
	pcall = zpcall,
	check = check,
	protect = protect,
	wrap = wrap,
}

if not ... then

	local errors = M

	local e1 = errors.errortype'e1'
	local e2 = errors.errortype('e2', 'e1')
	local e3 = errors.errortype'e3'

	local ok, e = errors.catch('e2 e3', function()

		local ok, e = errors.catch('e1', function()

			errors.raise('e2', 'imma e2')

		end)

		print'should not get here'

	end)

	if not ok then
		print('caught', e.classname, e.message)
	end

	errors.raise(e)

end

return M
