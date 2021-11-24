
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

local function errortype(classname, super, default_error_message)
	local class = classname and classes[classname]
	if not class then
		super = type(super) == 'string' and assert(classes[super]) or super or error
		class = object(super, {classname = classname, iserror = true,
			default_error_message = default_error_message or classname .. ' error'})
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

local function merge_option_tables(e, arg1, ...)
	if type(arg1) == 'table' then
		for k,v in pairs(arg1) do e[k] = v end
		return merge_option_tables(e, ...)
	else
		e.message = e.message or (... and string.format(...) or nil)
		return e
	end
end
function error:__call(arg1, ...)
	local e
	if type(arg1) == 'table' then
		e = merge_option_tables(object(self, arg1), ...)
	else
		e = object(self, {message = arg1 and string.format(arg1, ...) or nil})
	end
	e:init()
	return e
end

function error:__tostring()
	local s = self.traceback or self.message or self.default_error_message
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

The following is a error-handling mechanism to use when writing TCP-based
protocols. Use check(), checkp() and check_io() to raise errors inside
protocol methods and then wrap those methods in protect() to catch those
errors and have the method return `nil,err` instead of raising for those
errors (but not for other kinds of errors).

You should distinguish between multiple types of errors:

- Invalid API usage, i.e. bugs on this side, which should raise (but shouldn't
  happen in production). Use assert() for those.
- Response validation errors, i.e. bugs on the other side which shouldn't
  raise but they put the connection in an inconsistent state so the connection
  must be closed. Use checkp() short of "check protocol" for those.
- Request or response content validation errors, which can be user-corrected
  so mustn't raise and mustn't close the connection. Use check() for those.
- I/O errors, i.e. network failures which can be temporary and thus make the
  call retriable, so they must be distinguishable from other types of errors.
  Use check_io() for those. On the call side then check the error class for
  implementing retries.

Following this protocol should easily cut your network code in half, increase
its readability (no more error-handling noise) and its reliability (no more
confusion about when to raise and when not to or forgetting to handle an error).

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
	errors.raise(tcp_error({
		tcp = self and self.tcp,
		addtraceback = self and self.tracebacks,
	}, ...))
end

errors.tcp_protocol_errors = function(protocol)

	local protocol_error = errors.errortype(protocol, nil, protocol .. ' protocol error')
	local content_error  = errors.errortype(nil, nil, protocol .. ' error')

	protocol_error.init = tcp_error.init

	local function checker(create_error)
		return function(self, v, ...)
			if v then return v, ... end
			errors.raise(create_error({
				tcp = self and self.tcp,
				addtraceback = self and self.tracebacks,
			}, ...))
		end
	end
	local checkp = checker(protocol_error)
	local check  = checker(content_error)

	local classes = {[tcp_error]=1, [protocol_error]=1, [content_error]=1}

	local function protect(f)
		return errors.protect(classes, f)
	end

	return check_io, checkp, check, protect
end

--self test ------------------------------------------------------------------

if not ... then

	local check_io, checkp, check, protect = errors.tcp_protocol_errors'test'
	local t = {tcp = {close = function(self) self.closed = true end}, tracebacks = false}
	t.test0 = protect(function(t) check(t) end)
	t.test1 = protect(function(t) checkp(t, nil, 'see %d', 123) end)
	t.test2 = protect(function(t) check_io(t, nil, 'see %d', 321) end)
	t.test3 = protect(function(t) checkp(t) end)
	print(t:test0())
	assert(not t.tcp.closed)
	print(t:test1())
	assert(t.tcp.closed)
	print(t:test2())
	print(t:test3())

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
