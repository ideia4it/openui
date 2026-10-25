defmodule OpenUI.Test.ExampleUI do
  @moduledoc false

  use OpenUI.LiveView.Components,
    library: OpenUI.Test.ExampleLibrary,
    fields: %{
      "Input" => [name: "name", type: "input"],
      "Select" => [name: "name", type: "select"]
    },
    forms: %{"Form" => "name"}

  def stack(assigns), do: ~H|<div class="stack" data-direction={@direction}>{@children}</div>|
  def card(assigns), do: ~H|<section class="card"><h2>{@title}</h2>{@children}</section>|
  def text(assigns), do: ~H|<p class="text" data-variant={@variant}>{@text}</p>|

  def metric(assigns) do
    ~H"""
    <div class="metric" data-value={@value} data-loading={to_string(@loading)}>
      <span>{@label}</span>
    </div>
    """
  end

  def line_chart(assigns) do
    ~H"""
    <figure class="line-chart" data-points={length(@labels || [])}>{@series}</figure>
    """
  end

  def series(assigns), do: ~H|<span class="series">{@name}</span>|
  def table(assigns), do: ~H|<table><tr>{@columns}</tr></table>|

  def col(assigns) do
    ~H"""
    <th>{@label}<span :for={cell <- @data || []} class="cell">{cell}</span></th>
    """
  end

  def button(assigns) do
    ~H"""
    <button {@action || []}>{@label}</button>
    """
  end

  def form(assigns), do: ~H|<fieldset data-form={@name}>{@children}</fieldset>|

  def input(assigns) do
    ~H"""
    <input type="text" placeholder={@placeholder} {@bind || []} />
    <span :if={@error} class="field-error">{@error}</span>
    """
  end

  def select(assigns) do
    ~H"""
    <select data-bound={@value} {@bind || []}>{@items}</select>
    """
  end

  def select_item(assigns), do: ~H|<option value={@value}>{@label}</option>|
  def highlight(assigns), do: ~H|<aside class="highlight">{@content}</aside>|
end
