
## `local errors = require'errors'`

This is an API that adds structured exceptions to Lua. Exceptions, like
coroutines are not used very frequently in Lua because they solve
cross-cutting concerns(*) that don't appear very often in code. But when
they do appear, these devices are invaluable code decluttering tools.

Structured exceptions are an enhancement over string exceptions that enable
_selective catching_ and allow _providing a context_ for the failure to help
with recovery or logging.

> (*) Coroutines address the problem of inversion-of-control head-on.
Exceptions address the problem of recoverable failure head-on, so they're
most useful in network I/O contexts.

## API

-------------------------------------------------------- ---------------------
`errors.error`                                           base class for errors
`errors.error:init()`                                    stub: called after the error is created
`errors.errortype([classname], [super]) -> eclass`       create/get an error class
`eclass(...) -> e`                                       create an error object
`errors.new(classname, [e], ... | e) -> e`               create/wrap/pass-through an error object
`errors.is(v[, classes]) -> true|false`                  check an error object type
`errors.raise(classname,[e],... | e)`                    (create and) raise an error
`errors.catch([classes], f, ...) -> true,... | false,e`  pcall `f` and catch errors
`errors.pcall(f, ...) -> ...`                            pcall that stores traceback in `e.traceback`
`errors.check(v, ...) -> v | raise(...)`                 assert with specifying an error class
`errors.protect(classes, f) -> protected_f`              turn raising `f` into a `nil,e` function
`eclass:__call(...) -> e`                                error class constructor
`eclass:__tostring() -> s`                               to make `error(e)` work
`eclass.addtraceback`                                    add a traceback to errors
`e.message`                                              formatted error message
`e.traceback`                                            traceback at error site
-------------------------------------------------------- ---------------------

In the API `classes` can be given as `'classname1 ...'` or `{class1->true}`.
When in table form, you must include all the superclasses in the table as
they are not added automatically!

