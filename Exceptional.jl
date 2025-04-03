module Exceptional

export _restart_stack

struct Escape
	value::Any
	token::Symbol
end

struct Restart
	name::Symbol
	func::Function
	test::Union{Function, Nothing}
	report::Union{String, Nothing}
	interactive::Union{Function, Nothing}
end

const _handler_stack = Vector{Pair{Type, Function}}()
const _restart_stack = Vector{Restart}()

function to_escape(func)
	token = gensym("escape")

	try
		return func((value = nothing) -> begin
			throw(Escape(value, token))
		end)
	catch e
		if e isa Escape && e.token == token
			return e.value
		else
			rethrow()
		end
	end
end

function handling(func, handlers...)
	prev_handlers_count = length(_handler_stack)

	for handler in handlers
		pushfirst!(_handler_stack, handler)
	end

	try
		return func()
	finally
		while length(_handler_stack) > prev_handlers_count
			popfirst!(_handler_stack)
		end
	end
end

function with_restart(func, restarts...)
	prev_restarts_count = length(_restart_stack)

	for restart in restarts
		if restart isa Pair{Symbol, <:Function}
			pushfirst!(_restart_stack, process_restart(restart))
		elseif restart isa Tuple
			pushfirst!(_restart_stack, process_restart(restart...))
		else
			error("Invalid restart specification: $restart")
		end
	end

	try
		return func()
	finally
		while length(_restart_stack) > prev_restarts_count
			popfirst!(_restart_stack)
		end
	end
end

function process_restart(basic::Pair{Symbol, <:Function}, options...)

	test = nothing
	report = nothing
	interactive = nothing

	if isempty(options)
		return Restart(basic.first, basic.second, nothing, nothing, nothing)
	else
		for opt in options
			if opt isa Pair
				if opt.first == :test
					test = opt.second
				elseif opt.first == :report
					report = opt.second
				elseif opt.first == :interactive
					interactive = opt.second
				end
			end
		end
		return Restart(basic.first, basic.second, test, report, interactive)
	end
end

function available_restart(name)
	filter(_restart_stack) do restart
		if restart.test === nothing
			true
		else
			try
				restart.test(exception)
			catch
				false
			end
		end
	end
	return any(r -> r.name == name, _restart_stack)
end

function invoke_restart(name, args...)
	for restart in _restart_stack
		if restart.name == name
			if isempty(args) && restart.interactive !== nothing
				args = restart.interactive()
			end
			throw((restart, args...))
		end
	end
	error("No restart named $name is available")
end

function signal(exception)
	for (exception_type, handler_func) in _handler_stack
		if exception isa exception_type
			handler_func(exception)
		end
	end
	return nothing
end

function error(exception)
	for (exception_type, handler_func) in _handler_stack
		if exception isa exception_type
			try
				handler_func(exception)
			catch ex
				if ex isa Tuple && length(ex) >= 1 && ex[1] isa Restart
					restart = ex[1]
					args = length(ex) > 1 ? ex[2:end] : ()

					return restart.func(args...)
				else
					rethrow()
				end
			end
		end
	end
	throw(exception)
end


end # module
