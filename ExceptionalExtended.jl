module ExceptionalExtended

include("Exceptional.jl")
using ..Exceptional: handling, with_restart, Restart, _restart_stack, invoke_restart, to_escape, error

#############################################################
# User handling of restarts  +  Common Lisp Restart Options #
#############################################################

struct Abort
	value::Any
end

function prompt_for_input(type::Type)
	while true
		print("Enter a value [$type]: ")
		try
			input = readline()
			if type == String
				return input
			elseif type == Int
				return parse(Int, input)
			elseif type == Float64
				return parse(Float64, input)
			elseif type == Bool
				return lowercase(input) in ["true", "t", "yes", "y"]
			elseif type == Any
				return input
			else
				println("Can't parse input. Try again.")
			end
		catch e
			println("Invalid input. Please try again. Error: ", e)
		end
	end
end

function get_function_parameter_types(f::Function)
	methods_list = methods(f)

	if isempty(methods_list)
		return Type[]
	end

	method = first(methods_list)
	return collect(method.sig.parameters[2:end])
end

function interactive_restart_handler(exception)
	_available_restarts = filter((restart) -> restart.test == nothing || restart.test(exception) == true, _restart_stack)
	reverse!(_available_restarts)

	if isempty(_available_restarts)
		throw(exception)
	end

	println("An exception occurred: ", exception)
	println("Available restarts:")

	for (i, restart) in enumerate(_available_restarts)
		name = restart.name
		if restart.report === nothing
			println("  $i. $name")
		else
			println("  $i. $name: " * restart.report)
		end
	end

	println("  0. Abort (rethrow exception)")

	while true
		print("Choose a restart (enter number): ")
		try
			choice = parse(Int, readline())
			if choice == 0
				throw(Abort(exception))
			end

			if 1 <= choice <= length(_available_restarts)
				restart = _available_restarts[choice]

				if restart.interactive !== nothing
					return invoke_restart(restart.name, restart.interactive())
				else
					param_types = get_function_parameter_types(restart.func)

					args = if isempty(param_types)
						()
					else
						tuple(prompt_for_input.(param_types)...)
					end

					return invoke_restart(restart.name, args...)
				end
			else
				println("Invalid choice. Please try again.")
			end
		catch ex
			if ex[1] isa Restart || ex isa Abort
				rethrow()
			end
			println(ex)
			println("Invalid input. Please enter a number.")
		end
	end
end


##########
# Macros #
##########

# HANDLER_CASE

macro handler_case(expr, handlers...)

	handling_clauses = [
		:($(esc(handler.args[1])) => ($(esc(handler.args[2])) -> begin
			val = $(esc(handler.args[3]))
			escape_fn(val)
		end))
		for handler in handlers
	]

	quote
		to_escape() do escape_fn
			handling($(handling_clauses...)) do
				result = $(esc(expr))
			end
		end
	end
end

# RESTART CASE

macro restart_case(expr, restart_defs...)

	restart_clauses = map(restart_defs) do def
		name = def.args[1]
		params = def.args[2]
		body = def.args[3]

		if params == ()
			:($(esc(name)) => () -> $(esc(body)))
		else
			:($(esc(name)) => $(esc(params)) -> $(esc(body)))
		end
	end

	quote
		with_restart($(restart_clauses...)) do
			$(esc(expr))
		end
	end
end

end # module