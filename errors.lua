
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

local errors = {
	error = error,
	errortype = errortype,
	new = newerror,
	is = iserrorof,
	raise = raise,
	catch = catch,
	pcall = zpcall,
	check = check,
	protect = protect,
}

--[[--------------------------------------------------------------------------

Errors raised with with check() and check_io() instead of assert() or error()
enable methods wrapped with protect() to catch those errors, free temporary
resources and return nil,err instead of raising.

We distinguish between many types of errors:

- input validation errors, which can be user-corrected so they mustn't raise.
- invalid API usage, i.e. bugs on this side, which raise.
- response validation errors, i.e. bugs on the other side which don't raise.
- I/O errors, i.e. network failures which can be temporary and thus make the
  call retriable, so they must be distinguishable from other types of errors.

--]]--------------------------------------------------------------------------

local tcp_error = errors.errortype'tcp'

function tcp_error:init()
	if self.tcp then
		self.tcp:close(0)
		self.tcp = nil
	end
end

local function check_io(self, v, ...)
	if v then return v, ... end
	local err, errcode = ...
	errors.raise(tcp_error{tcp = self and self.tcp, message = err, errorcode = errcode,
		addtraceback = self and self.tracebacks})
end

errors.tcp_protocol_errors = function(protocol)

	local prot_error = errors.errortype(protocol)

	local function check(self, v, ...)
		if v then return v, ... end
		local err, errcode = ...
		errors.raise(prot_error{tcp = self.tcp, message = err, errorcode = errcode,
			addtraceback = self.tracebacks})
	end

	prot_error.init = tcp_error.init

	local function protect(f)
		return errors.protect('tcp '..protocol, f)
	end

	return check_io, check, protect
end

--self test ------------------------------------------------------------------

if not ... then

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

return errors
