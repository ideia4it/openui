if Code.ensure_loaded?(Phoenix.Component) do
  defmodule OpenUI.LiveView.HTML do
    @moduledoc false
    # Renders the evaluated tree to HTML with the host's function components,
    # one component at a time inside a rescue (language.md, section 10: a
    # renderer that throws must not crash the host). A component that raises
    # is left out and reported as runtime-error. Rendering to HTML here, and
    # not leaving it to LiveView's diff, is what makes the rescue possible: the
    # cost is that a component that changes is sent again whole.

    require Logger

    alias Phoenix.HTML.Safe

    alias OpenUI.{ActionPlan, Binding, Element, Error, Library, Runtime, Unknown}

    @doc false
    def render(%Runtime{} = runtime, components, opts) do
      ctx = %{
        runtime: runtime,
        components: components,
        library: Library.resolve(components.__openui__(:library)),
        fields: components.__openui__(:fields),
        target: Keyword.get(opts, :target),
        dom_id: Keyword.get(opts, :dom_id, "openui"),
        unknown: Keyword.get(opts, :unknown),
        loading?: Runtime.query_status(runtime).loading?
      }

      {html, errors} = render_value(Runtime.tree(runtime), ctx, [])
      {html || {:safe, ""}, Enum.reverse(errors)}
    end

    defp render_value(%Element{} = element, ctx, errors), do: render_element(element, ctx, errors)

    defp render_value(%Unknown{} = unknown, ctx, errors),
      do: {render_unknown(unknown, ctx), errors}

    defp render_value(list, ctx, errors) when is_list(list) do
      {items, errors} = Enum.map_reduce(list, errors, &render_value(&1, ctx, &2))
      {Enum.reject(items, &is_nil/1), errors}
    end

    defp render_value(value, _ctx, errors), do: {value, errors}

    defp render_element(element, ctx, errors) do
      component = Library.component(ctx.library, element.type)
      {assigns, errors} = assigns(element, component, ctx, errors)
      fun = ctx.components.__openui__({:function, element.type})

      try do
        rendered = apply(ctx.components, fun, [assigns])
        {{:safe, Safe.to_iodata(rendered)}, errors}
      rescue
        exception ->
          message = failure_message(element.type, exception)

          Logger.error(
            "OpenUI could not render #{element.type} (statement #{element.statement_id || "inline"}): " <>
              Exception.format(:error, exception, __STACKTRACE__)
          )

          error = %Error{
            source: :runtime,
            code: "runtime-error",
            component: element.type,
            statement_id: element.statement_id,
            message: message
          }

          {nil, [error | errors]}
      end
    end

    defp failure_message(type, %ArgumentError{message: "cannot convert component" <> _rest}),
      do: "catalog component #{type} cannot render a live component"

    defp failure_message(type, exception),
      do: "Rendering #{type} failed: " <> Exception.message(exception)

    defp assigns(element, component, ctx, errors) do
      props = if component, do: component.props, else: []

      {pairs, errors} =
        Enum.map_reduce(props, errors, fn prop, errors ->
          {value, errors} =
            prop_assign(element, prop, Map.get(element.props, prop.name), ctx, errors)

          # Prop names come from the library, a finite set the host defined.
          {{String.to_atom(prop.name), value}, errors}
        end)

      assigns =
        Map.merge(Map.new(pairs), %{
          __changed__: nil,
          bind: bind(element, ctx),
          error: Runtime.field_error(ctx.runtime, element.key),
          loading: ctx.loading?
        })

      {assigns, errors}
    end

    defp prop_assign(element, %{kind: :action, name: name}, %ActionPlan{}, ctx, errors),
      do: {action_attributes(element.key, name, ctx), errors}

    defp prop_assign(_element, %{kind: :action}, _value, _ctx, errors), do: {nil, errors}

    defp prop_assign(_element, _prop, %Binding{name: name}, ctx, errors),
      do: {ctx.runtime |> Runtime.state() |> Map.get(name) |> unwrap(), errors}

    defp prop_assign(_element, %{kind: :components}, value, ctx, errors),
      do: render_slot(value, ctx, errors)

    defp prop_assign(_element, _prop, value, ctx, errors), do: render_value(value, ctx, errors)

    # Data that reaches a component slot at runtime, such as a query result in a
    # children list, is left out as the official renderer does; text still shows.
    defp render_slot(list, ctx, errors) when is_list(list) do
      {items, errors} = Enum.map_reduce(list, errors, &render_slot(&1, ctx, &2))
      {Enum.reject(items, &is_nil/1), errors}
    end

    defp render_slot(value, _ctx, errors) when is_map(value) and not is_struct(value),
      do: {nil, errors}

    defp render_slot(value, ctx, errors), do: render_value(value, ctx, errors)

    defp action_attributes(key, prop, ctx) do
      [{"type", "button"}, {"phx-click", "openui:action"}] ++
        if(ctx.target, do: [{"phx-target", ctx.target}], else: []) ++
        [{"phx-value-key", key}, {"phx-value-prop", prop}]
    end

    defp bind(element, ctx) do
      if Map.has_key?(ctx.fields, element.type) do
        [
          id: "#{ctx.dom_id}-#{element.key}",
          name: "openui[#{element.key}]",
          value: Runtime.field_value(ctx.runtime, element.key)
        ]
      end
    end

    defp unwrap(%{"value" => value, "componentType" => _type}), do: value
    defp unwrap(value), do: value

    defp render_unknown(_unknown, %{unknown: nil}), do: nil

    defp render_unknown(unknown, ctx) do
      ctx.unknown.(%Error{
        source: :parser,
        code: "unknown-component",
        component: unknown.type,
        statement_id: unknown.statement_id,
        message: ~s(Unknown component "#{unknown.type}")
      })
    end
  end
end
