defmodule ConsoleOps.Registry do
  @moduledoc """
  A DSL to declare console commands.

  `use ConsoleOps.Registry` in a module, then group ops in `namespace/2`
  blocks:

      defmodule MyApp.Console do
        use ConsoleOps.Registry

        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state" do
            mode :readonly
            tags [:support, :incident]
            param :invoice_id, :id, required: true, doc: "The invoice to inspect"
            run &MyApp.Billing.Console.invoice_state/2
          end
        end
      end

  Each `op/3` becomes a `ConsoleOps.Command` with the id `"billing.invoice_state"`.
  Inside an op:

    * `mode` - required, one of `:readonly`, `:mutation` or `:destructive`
    * `tags` - optional, a list of atoms
    * `param` - optional and repeatable, takes the arguments of
      `ConsoleOps.Param.new!/3`
    * `run` - required, `fn params, ctx -> ... end`, a local capture
      `&fun/2` or a remote capture `&Mod.fun/2`. `{Mod, :fun}` tuples and
      captures such as `&f(&1, &2)` are not accepted.

  Namespace and op names must be literal atoms in lowercase snake_case, such as
  `:billing_v2`. A namespace block may be repeated, but namespaces do not nest
  and every op id must be unique.

  Mistakes in the DSL raise a `CompileError` with the file and line of the
  faulty call.

  ## Introspection

  The registry module gets a function `__console_ops__(:commands)`, which
  returns the list of `ConsoleOps.Command` structs in declaration order:

      [command] = MyApp.Console.__console_ops__(:commands)
      command.id
      #=> "billing.invoice_state"

  When at least one op is declared, the module also defines
  `__console_ops__(:run, id, params, ctx)`. It calls the `run` of the op with
  that id and returns what it returns. It is the entry point for code that
  executes commands, and is not meant to be called directly.

  ## Evaluation order

  The summary, mode, tags and param arguments are evaluated in the module body,
  where the op is declared, as `field` is in Ecto. A param default can therefore
  read a module attribute:

      @limit 10

      namespace :billing do
        op :invoices, "List recent invoices" do
          mode :readonly
          param :limit, :integer, default: @limit
          run &MyApp.Billing.Console.invoices/2
        end
      end

  Commands are stored in the compiled module, so a param default cannot be, or
  contain, an anonymous function, a reference or a port; such a default raises
  a `CompileError` at its `param` line.

  `run` bodies compile where the op is declared, so aliases, imports, requires
  and module attributes resolve as anywhere else in Elixir. Captures like
  `&Mod.fun/2` do not make the registry depend on `Mod` at compile time.
  """

  alias ConsoleOps.Command
  alias ConsoleOps.Param

  @modes Command.modes()
  @attribute :console_ops_ops
  @op_calls "expected one of: mode/1, tags/1, param/2, param/3, run/1"

  @doc """
  Imports `namespace/2` and `op/3` and prepares the module to collect ops.
  """
  defmacro __using__(_opts) do
    quote do
      import ConsoleOps.Registry, only: [namespace: 2, op: 3]
      Module.register_attribute(__MODULE__, unquote(@attribute), accumulate: true)
      @before_compile ConsoleOps.Registry
    end
  end

  @doc """
  Groups ops under a namespace. Only `op/3` calls are allowed inside.

  The namespace is the first part of the id of each op in the block.
  """
  defmacro namespace(name, do: block) do
    env = __CALLER__
    namespace = validate_namespace!(env, env.line, name)
    ops = for expr <- block_to_list(block), do: expand_op(env, namespace, expr)

    {:__block__, [], ops}
  end

  @doc """
  Declares a command with a name and a one-line summary.

  It can only be used inside a `namespace/2` block. See the module docs for
  the calls allowed in the `do` block.
  """
  defmacro op(name, _summary, _block) do
    env = __CALLER__
    message = "op #{Macro.to_string(name)} must be defined inside a namespace block"

    quote do
      ConsoleOps.Registry.__compile_error__!(
        unquote(env.file),
        unquote(env.line),
        unquote(message)
      )
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    ops = env.module |> Module.get_attribute(@attribute) |> Enum.reverse()
    commands = ops |> Enum.map(fn {command, _run_name} -> command end) |> Macro.escape()
    run_clauses = for {command, run_name} <- ops, do: run_clause(command, run_name)

    quote do
      @doc false
      def __console_ops__(:commands), do: unquote(commands)
      unquote_splicing(run_clauses)
    end
  end

  defp run_clause(command, run_name) do
    quote do
      @doc false
      def __console_ops__(:run, unquote(command.id), params, ctx) do
        unquote(run_name)(params, ctx)
      end
    end
  end

  @doc false
  @spec __compile_error__!(String.t(), pos_integer(), String.t()) :: no_return()
  def __compile_error__!(file, line, description) do
    raise CompileError, file: file, line: line, description: description
  end

  @doc false
  @spec __op__(module(), map()) :: :ok
  def __op__(module, op) do
    id = "#{op.namespace}.#{op.name}"

    validate_unique!(module, op, id)
    validate_summary!(op, id)

    command = %Command{
      id: id,
      namespace: op.namespace,
      name: op.name,
      summary: op.summary,
      mode: validate_mode!(op, id),
      tags: validate_tags!(op, id),
      params: build_params!(op, id)
    }

    Module.put_attribute(module, @attribute, {command, op.run_name})
  end

  defp block_to_list({:__block__, _meta, exprs}), do: exprs
  defp block_to_list(expr), do: [expr]

  defp validate_namespace!(env, line, name) do
    if valid_name?(name) do
      name
    else
      __compile_error__!(
        env.file,
        line,
        "invalid namespace name: expected a lowercase snake_case atom such as :billing, " <>
          "got: #{Macro.to_string(name)}"
      )
    end
  end

  defp validate_op_name!(env, line, namespace, name) do
    if valid_name?(name) do
      name
    else
      __compile_error__!(
        env.file,
        line,
        "invalid op name in namespace #{inspect(namespace)}: expected a lowercase " <>
          "snake_case atom such as :invoice_state, got: #{Macro.to_string(name)}"
      )
    end
  end

  defp valid_name?(name) do
    is_atom(name) and name not in [nil, true, false] and
      Atom.to_string(name) =~ ~r/\A[a-z][a-z0-9_]*\z/
  end

  defp expand_op(env, namespace, {:op, meta, [name, summary, [do: block]]}) do
    line = line(meta, env.line)
    name = validate_op_name!(env, line, namespace, name)
    id = "#{namespace}.#{name}"
    body = collect_calls(env, id, line, block_to_list(block))

    op_call(env, line, namespace, name, summary, body, id)
  end

  defp expand_op(env, namespace, {:op, meta, [name | _args]}) do
    __compile_error__!(
      env.file,
      line(meta, env.line),
      "op #{Macro.to_string(name)} in namespace #{inspect(namespace)} expects a summary and " <>
        "a do block, such as: op #{Macro.to_string(name)}, \"Summary\" do ... end"
    )
  end

  defp expand_op(env, namespace, {:namespace, meta, [name | _args]}) do
    __compile_error__!(
      env.file,
      line(meta, env.line),
      "namespace #{Macro.to_string(name)} cannot be nested inside namespace " <>
        "#{inspect(namespace)}, namespaces do not nest"
    )
  end

  defp expand_op(env, namespace, {{:., _, [receiver, fun]}, meta, args})
       when is_atom(fun) and is_list(args) do
    __compile_error__!(
      env.file,
      line(meta, env.line),
      "unknown call #{remote_call(receiver, fun, args)} in namespace #{inspect(namespace)}, " <>
        "expected op/3"
    )
  end

  defp expand_op(env, namespace, {call, meta, args}) when is_atom(call) and is_list(args) do
    __compile_error__!(
      env.file,
      line(meta, env.line),
      "unknown call #{call}/#{length(args)} in namespace #{inspect(namespace)}, expected op/3"
    )
  end

  defp expand_op(env, namespace, expr) do
    __compile_error__!(
      env.file,
      expr_line(expr, env.line),
      "unexpected expression #{Macro.to_string(expr)} in namespace #{inspect(namespace)}, " <>
        "expected op/3"
    )
  end

  defp collect_calls(env, id, op_line, exprs) do
    initial = %{mode: nil, tags: nil, run: nil, params: []}
    Enum.reduce(exprs, initial, &collect_call(env, id, op_line, &1, &2))
  end

  defp collect_call(env, id, op_line, {call, meta, [value]}, acc)
       when call in [:mode, :tags, :run] do
    line = line(meta, op_line)

    case acc do
      %{^call => nil} ->
        %{acc | call => {line, value}}

      _ ->
        __compile_error__!(
          env.file,
          line,
          "duplicate #{call} for op #{inspect(id)}, #{call} can be given at most once"
        )
    end
  end

  defp collect_call(_env, _id, op_line, {:param, meta, [name, type | opts]}, acc)
       when length(opts) <= 1 do
    line = line(meta, op_line)
    param = quote do: {unquote(line), unquote(name), unquote(type), unquote(List.first(opts, []))}

    %{acc | params: acc.params ++ [param]}
  end

  defp collect_call(env, id, op_line, {{:., _, [receiver, fun]}, meta, args}, _acc)
       when is_atom(fun) and is_list(args) do
    __compile_error__!(
      env.file,
      line(meta, op_line),
      "unknown call #{remote_call(receiver, fun, args)} in op #{inspect(id)}, #{@op_calls}"
    )
  end

  defp collect_call(env, id, op_line, {call, meta, args}, _acc)
       when is_atom(call) and is_list(args) do
    __compile_error__!(
      env.file,
      line(meta, op_line),
      "unknown call #{call}/#{length(args)} in op #{inspect(id)}, #{@op_calls}"
    )
  end

  defp collect_call(env, id, op_line, expr, _acc) do
    __compile_error__!(
      env.file,
      expr_line(expr, op_line),
      "unexpected expression #{Macro.to_string(expr)} in op #{inspect(id)}, #{@op_calls}"
    )
  end

  defp remote_call(receiver, fun, args), do: "#{Macro.to_string(receiver)}.#{fun}/#{length(args)}"

  defp op_call(env, line, namespace, name, summary, body, id) do
    {mode_line, mode} = body.mode || missing_mode!(env, line, id)
    {tags_line, tags} = body.tags || {line, []}
    {run_line, run} = body.run || missing_run!(env, line, id)

    validate_run!(env, run_line, id, run)

    # Safe: built only from namespace/op literals validated as snake_case at compile time.
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    run_name = :"__console_ops_run__#{id}"

    quote line: line do
      ConsoleOps.Registry.__op__(__MODULE__, %{
        file: unquote(env.file),
        namespace: unquote(namespace),
        name: unquote(name),
        line: unquote(line),
        summary: unquote(summary),
        mode: {unquote(mode_line), unquote(mode)},
        tags: {unquote(tags_line), unquote(tags)},
        params: unquote(body.params),
        run_name: unquote(run_name)
      })

      defp unquote(run_name)(params, ctx), do: unquote(run).(params, ctx)
    end
  end

  @spec missing_mode!(Macro.Env.t(), pos_integer(), String.t()) :: no_return()
  defp missing_mode!(env, line, id) do
    modes = Enum.map_join(@modes, ", ", &"mode #{inspect(&1)}")
    __compile_error__!(env.file, line, "op #{inspect(id)} is missing mode, add one of: #{modes}")
  end

  @spec missing_run!(Macro.Env.t(), pos_integer(), String.t()) :: no_return()
  defp missing_run!(env, line, id) do
    __compile_error__!(
      env.file,
      line,
      "op #{inspect(id)} is missing run, add run fn params, ctx -> ... end or run &Mod.fun/2"
    )
  end

  defp validate_run!(env, line, id, run) do
    if valid_run?(run) do
      :ok
    else
      __compile_error__!(
        env.file,
        line,
        "invalid run for op #{inspect(id)}: expected fn params, ctx -> ... end, " <>
          "&fun/2 or &Mod.fun/2, got: #{Macro.to_string(run)}"
      )
    end
  end

  defp valid_run?({:fn, _meta, clauses}), do: Enum.all?(clauses, &clause_takes_two?/1)

  defp valid_run?({:&, _meta, [{:/, _, [{name, _, context}, 2]}]})
       when is_atom(name) and is_atom(context),
       do: true

  defp valid_run?({:&, _meta, [{:/, _, [{{:., _, [_module, fun]}, _, []}, 2]}]})
       when is_atom(fun),
       do: true

  defp valid_run?(_run), do: false

  defp clause_takes_two?({:->, _meta, [[{:when, _, args_and_guard}], _body]}),
    do: length(args_and_guard) == 3

  defp clause_takes_two?({:->, _meta, [args, _body]}), do: length(args) == 2

  defp line(meta, default_line), do: Keyword.get(meta, :line, default_line)

  defp expr_line({_form, meta, _args}, default_line) when is_list(meta),
    do: line(meta, default_line)

  defp expr_line(_literal, default_line), do: default_line

  defp validate_unique!(module, op, id) do
    taken? =
      module
      |> Module.get_attribute(@attribute)
      |> Enum.any?(fn {c, _run_name} -> c.id == id end)

    if taken? do
      __compile_error__!(
        op.file,
        op.line,
        "duplicate op #{inspect(id)}, op ids must be unique within a registry"
      )
    end

    :ok
  end

  defp validate_summary!(op, id) do
    if is_binary(op.summary) and String.trim(op.summary) != "" do
      :ok
    else
      __compile_error__!(
        op.file,
        op.line,
        "invalid summary for op #{inspect(id)}: expected a non-blank string, " <>
          "got: #{inspect(op.summary)}"
      )
    end
  end

  defp validate_mode!(%{mode: {_line, mode}}, _id) when mode in @modes, do: mode

  defp validate_mode!(%{mode: {line, mode}, file: file}, id) do
    suggestion = if is_atom(mode), do: Param.closest(Atom.to_string(mode), @modes)

    hint =
      if suggestion do
        "did you mean #{inspect(suggestion)}?"
      else
        "supported modes are: #{inspect(@modes)}"
      end

    __compile_error__!(file, line, "unknown mode #{inspect(mode)} for op #{inspect(id)}, #{hint}")
  end

  defp validate_tags!(%{tags: {line, tags}, file: file}, id) do
    if atom_list?(tags) do
      tags
    else
      __compile_error__!(
        file,
        line,
        "invalid tags for op #{inspect(id)}: expected a list of atoms, got: #{inspect(tags)}"
      )
    end
  end

  defp atom_list?([]), do: true
  defp atom_list?([tag | rest]) when is_atom(tag), do: atom_list?(rest)
  defp atom_list?(_other), do: false

  defp build_params!(op, id) do
    op.params |> Enum.reduce([], &add_param!(op.file, id, &1, &2)) |> Enum.reverse()
  end

  defp add_param!(file, id, {line, name, type, opts}, built) do
    param = new_param!(file, line, name, type, opts)

    if Enum.any?(built, &(&1.name == param.name)) do
      __compile_error__!(
        file,
        line,
        "duplicate param #{inspect(param.name)} for op #{inspect(id)}, " <>
          "each param can be declared at most once"
      )
    end

    [param | built]
  end

  defp new_param!(file, line, name, type, opts) do
    param = Param.new!(name, type, opts)
    validate_storable!(file, line, param)
    param
  rescue
    error in ArgumentError -> __compile_error__!(file, line, error.message)
  end

  defp validate_storable!(file, line, param) do
    _ = Macro.escape(param.default)
    :ok
  rescue
    ArgumentError ->
      __compile_error__!(
        file,
        line,
        "invalid value for :default option of param #{inspect(param.name)}: expected a value " <>
          "that can be stored in compiled code, got: #{inspect(param.default)}"
      )
  end
end
