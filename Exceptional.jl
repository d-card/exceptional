module Exceptional

struct Escape
	value::Any
	token::Symbol
end

struct Restart
	callback::Any
end

const _handler_stack = Vector{Pair{Type, Function}}()
const _restart_stack = Vector{Pair{Symbol, Function}}()

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
		pushfirst!(_restart_stack, restart)
	end

	try
		return func()
	finally
		while length(_restart_stack) > prev_restarts_count
			popfirst!(_restart_stack)
		end
	end
end

function available_restart(name)
	return any(r -> r[1] == name, _restart_stack)
end

function invoke_restart(name, args...)
	for (restart_name, restart_func) in _restart_stack
		if restart_name == name
			throw(Restart(restart_func(args...)))
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
				if ex isa Restart
					return ex.callback
				end
				rethrow()
			end
		end
	end
	throw(exception)
end

############
# EXAMPLES #
############

struct DivisionByZero <: Exception end

# 1.
function reciprocal(x)
	x == 0 ? error(DivisionByZero()) : 1 / x
end

# println(reciprocal(10))
# println(reciprocal(0))

# 2.
# handling(() -> reciprocal(0), DivisionByZero => c -> println("I saw a division by zero"))

# handling(DivisionByZero =>
# 	(c) -> println("I saw it too")) do
# 	handling(DivisionByZero =>
# 		(c) -> println("I saw a division by zero")) do
# 		reciprocal(0)
# 	end
# end

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

# println(mystery(0))
# println(mystery(1))
# println(mystery(2))

# 4.
# println(to_escape() do exit
# 	handling(DivisionByZero =>
# 		(c) -> (println("I saw it too"); exit("Done"))) do
# 		handling(DivisionByZero =>
# 			(c) -> println("I saw a division by zero")) do
# 			reciprocal(0)
# 		end
# 	end
# end)

# println(to_escape() do exit
# 	handling(DivisionByZero =>
# 		(c) -> println("I saw it too")) do
# 		handling(DivisionByZero =>
# 			(c) -> (println("I saw a division by zero");
# 			exit("Done"))) do
# 			reciprocal(0)
# 		end
# 	end
# end)

# 5.
function reciprocal(value::Int)
	with_restart(:return_zero => () -> 0,
		:return_value => identity,
		:retry_using => reciprocal) do
		value == 0 ? error(DivisionByZero()) : 1 / value
	end
end

# println(handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
# 	reciprocal(0)
# end)

# println(handling(DivisionByZero => (c) -> invoke_restart(:return_value, 123)) do
# 	reciprocal(0)
# end)

# println(handling(DivisionByZero => (c) -> invoke_restart(:retry_using, 10)) do
# 	reciprocal(0)
# end)

# 6.
# println(handling(DivisionByZero =>
# 	(c) -> for restart in (:return_one, :return_zero, :die_horribly)
# 		if available_restart(restart)
# 			invoke_restart(restart)
# 		end
# 	end) do
# 	reciprocal(0)
# end)

# 7.
function infinity()
	with_restart(:just_do_it => () -> 1 / 0) do
		reciprocal(0)
	end
end

# println(handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
# 	infinity()
# end)

# println(handling(DivisionByZero => (c) -> invoke_restart(:return_value, 1)) do
# 	infinity()
# end)

# println(handling(DivisionByZero => (c) -> invoke_restart(:retry_using, 10)) do
# 	infinity()
# end)

# println(handling(DivisionByZero => (c) -> invoke_restart(:just_do_it)) do
# 	infinity()
# end)

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

# print_line("Hi, everybody! How are you feeling today?\n")

# println(to_escape() do exit
# 	handling(LineEndLimit => (c) -> exit()) do
# 		print_line("Hi, everybody! How are you feeling today?")
# 	end
# end)

# handling(LineEndLimit => (c) -> println()) do
# 	print_line("Hi, everybody! How are you feeling today?")
# end

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

# println(handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
# 	reciprocal2(0)
# end)


end # module
