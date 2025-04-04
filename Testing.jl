include("Exceptional.jl")
include("ExceptionalExtended.jl")

using .Exceptional: handling, with_restart, Escape, Restart, to_escape, available_restart, invoke_restart, signal, error, _restart_stack
using .ExceptionalExtended: interactive_restart_handler, get_function_parameter_types, prompt_for_input, @handler_case, @restart_case

###########################
# EXAMPLES EXCEPTIONAL.JL #
###########################

struct DivisionByZero <: Exception end

# 1.
function reciprocal(x)
	x == 0 ? error(DivisionByZero()) : 1 / x
end

println(reciprocal(10))
println(reciprocal(0))

# 2.
handling(() -> reciprocal(0), DivisionByZero => c -> println("I saw a division by zero"))

handling(DivisionByZero =>
	(c) -> println("I saw it too")) do
	handling(DivisionByZero =>
		(c) -> println("I saw a division by zero")) do
		reciprocal(0)
	end
end

# 3.
function mystery(n)
	1 +
	to_escape() do outer
		1 +
		to_escape() do inner
			1 +
			if n == 0
				inner(1)
			elseif n == 1
				outer(1)
			else
				1
			end
		end
	end
end

println(mystery(0))
println(mystery(1))
println(mystery(2))

# 4.
println(to_escape() do exit
	handling(DivisionByZero =>
		(c) -> (println("I saw it too"); exit("Done"))) do
		handling(DivisionByZero =>
			(c) -> println("I saw a division by zero")) do
			reciprocal(0)
		end
	end
end)

println(to_escape() do exit
	handling(DivisionByZero =>
		(c) -> println("I saw it too")) do
		handling(DivisionByZero =>
			(c) -> (println("I saw a division by zero");
			exit("Done"))) do
			reciprocal(0)
		end
	end
end)

# 5.
function reciprocal(value::Int)
	with_restart(:return_zero => () -> 0,
		:return_value => identity,
		:retry_using => reciprocal) do
		value == 0 ? error(DivisionByZero()) : 1 / value
	end
end

println(handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
	reciprocal(0)
end)

println(handling(DivisionByZero => (c) -> invoke_restart(:return_value, 123)) do
	reciprocal(0)
end)

println(handling(DivisionByZero => (c) -> invoke_restart(:retry_using, 10)) do
	reciprocal(0)
end)

# 6.
println(handling(DivisionByZero =>
	(c) -> for restart in (:return_one, :return_zero, :die_horribly)
		if available_restart(restart)
			invoke_restart(restart)
		end
	end) do
	reciprocal(0)
end)

# 7.
function infinity()
	with_restart(:just_do_it => () -> 1 / 0) do
		reciprocal(0)
	end
end

println(handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
	infinity()
end)

println(handling(DivisionByZero => (c) -> invoke_restart(:return_value, 1)) do
	infinity()
end)

println(handling(DivisionByZero => (c) -> invoke_restart(:retry_using, 10)) do
	infinity()
end)

println(handling(DivisionByZero => (c) -> invoke_restart(:just_do_it)) do
	infinity()
end)

# 8.
struct LineEndLimit <: Exception
end

function print_line(str, line_end = 20)
	let col = 0
		for c in str
			print(c)
			col += 1
			if col == line_end
				signal(LineEndLimit())
				col = 0
			end
		end
	end
end

print_line("Hi, everybody! How are you feeling today?\n")

to_escape() do exit
	handling(LineEndLimit => (c) -> exit()) do
		print_line("Hi, everybody! How are you feeling today?")
	end
end

handling(LineEndLimit => (c) -> println()) do
	print_line("Hi, everybody! How are you feeling today?")
end

# Restarts encadeados com o mesmo nome
function reciprocal2(value::Int)
	with_restart(:return_zero => () -> 0,
		:return_value => identity,
		:retry_using => reciprocal2) do
		with_restart(:return_zero => () -> 1,
			:return_value => identity,
			:retry_using => reciprocal2) do
			value == 0 ? error(DivisionByZero()) : 1 / value
		end
	end
end

println(handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
	reciprocal2(0)
end)


###################################
# EXAMPLES EXCEPTIONALEXTENDED.JL #
###################################


####################   USER HANDLING OF RESTARTS   ######################

function reciprocal(value::Int)
	with_restart(:return_zero => () -> 0,
		:return_value => identity,
		:retry_using => reciprocal) do
		value == 0 ? error(DivisionByZero()) : 1 / value
	end
end

try
	handling(DivisionByZero => interactive_restart_handler) do
		result = reciprocal(0)
		println("Result: ", result)
	end
catch e
	println("Unhandled exception: ", e)
end

####################   COMMON LISP RESTART OPTIONS   ####################

function reciprocal_interactive(value::Int)
	with_restart(
		(:return_zero => () -> 0, :report => "Returns the value 0."),
		(:return_value => identity, :report => "Returns the inserted value."),
		(:retry_using => reciprocal_interactive, :report => "Retries with inserted value."),
		(:square => (x::Int) -> x^2, :test => (c) -> c isa DivisionByZero, :report => "Squares the inserted value."),
		(:bad_restart => (x::Int, y::Int) -> x + y,
			:test => (c) -> c isa Int,
			:report => "Adds two integers."),
		(:return_symmetrical => (x::Int) -> -x,
			:interactive => () -> begin
				print("Enter a number [Int64]: ")
				parse(Int, readline())
			end,
			:report => "Returns the symmetrical of the inserted value."),
	) do
		value == 0 ? error(DivisionByZero()) : 1 / value
	end
end

println(handling(DivisionByZero => (c) -> invoke_restart(:square, 10)) do
	reciprocal_interactive(0)
end)

try
	handling(DivisionByZero => interactive_restart_handler) do
		result = reciprocal_interactive(0)
		println("Result: ", result)
	end
catch e
	println("Unhandled exception: ", e)
end

#############################    MACROS    ##############################

function reciprocal(x)
	x == 0 ? error(DivisionByZero()) : 1 / x
end

###  @handler_case  ####

# Simple handler case
result = @handler_case(reciprocal(0), (DivisionByZero, c, println("Handled: ", c)))
println("Result: ", result)

# With return value
result = @handler_case(reciprocal(0), (DivisionByZero, c, (println("Handled"); 42)))
println("Result: ", result)


result = @handler_case(reciprocal(0),
	(DivisionByZero, c, begin
		println("Divided by zero!")
		42  # Return value
	end),
	(OverflowError, e, begin
		println("Overflow occurred!")
		escape_fn(100)  # Explicit escape
	end))

println("Final result: ", result)

@handler_case(reciprocal(0),
	(DivisionByZero, c, 42),  # Returns 42
	(OverflowError, e, 0))


@handler_case(           # Outer case
	@handler_case(       # Inner case
		error(DivisionByZero()),
		(DivisionByZero, c, :inner)),
	(DivisionByZero, c, :outer))
# Returns :inner

###  @restart_case  ####

reciprocal3(x) = @restart_case(
	x == 0 ? error(DivisionByZero()) : 1 / x,
	(:return_zero, (), 0),  # Empty tuple for no parameters
	(:return_value, (val), val),
	(:retry_with, (new_x), reciprocal(new_x)),
	(:sum_for_no_reason, (x, y, z), x + y + z)
)

result = handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
	reciprocal3(0)
end
println("Result: ", result)
result = handling(DivisionByZero => (c) -> invoke_restart(:return_value, 15)) do
	reciprocal3(0)
end
println("Result: ", result)
result = handling(DivisionByZero => (c) -> invoke_restart(:retry_with, 10)) do
	reciprocal3(0)
end
println("Result: ", result)
result = handling(DivisionByZero => (c) -> invoke_restart(:sum_for_no_reason, 2, 3, 6)) do
	reciprocal3(0)
end
println("Result: ", result)

# Nested
function nested()
	@restart_case(
		@restart_case(
			error(DivisionByZero()),
			(:inner, (), "inner")
		),
		(:outer, (), "outer")
	)
end

handling(DivisionByZero => _ -> invoke_restart(:inner)) do
	nested()
end

handling(DivisionByZero => _ -> invoke_restart(:outer)) do
	nested()
end