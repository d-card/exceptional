module InteractiveRestarts

include("Exceptional.jl")
using .Exceptional: handling, DivisionByZero, with_restart, reciprocal, Restart

#############################
# User handling of restarts #
#############################

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
	if isempty(Exceptional._restart_stack)
		throw(exception)
	end

	println("An exception occurred: ", exception)
	println("Available restarts:")
	for (i, (name, _)) in enumerate(Exceptional._restart_stack)
		println("  $i. $name")
	end
	println("  0. Abort (rethrow exception)")

	while true
		print("Choose a restart (enter number): ")
		try
			choice = parse(Int, readline())
			if choice == 0
				throw(Abort(exception))
			end

			if 1 <= choice <= length(Exceptional._restart_stack)
				restart_name, restart_func = Exceptional._restart_stack[choice]

				param_types = get_function_parameter_types(restart_func)

				args = if isempty(param_types)
					()
				else
					tuple(prompt_for_input.(param_types)...)
				end

				return Exceptional.invoke_restart(restart_name, args...)
			else
				println("Invalid choice. Please try again.")
			end
		catch ex
			if ex isa Restart || ex isa Abort
				rethrow()
			end
			println(ex)
			println("Invalid input. Please enter a number.")
		end
	end
end

###############################
# Common Lisp Restart Options #
###############################

##########
# Macros #
##########

############
# EXAMPLES #
############

try
	handling(DivisionByZero => interactive_restart_handler) do
		result = reciprocal(0)
		println("Result: ", result)
	end
catch e
	println("Unhandled exception: ", e)
end

end # module
