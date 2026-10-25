defmodule OpenUI.Prompt.Text do
  @moduledoc false
  # The fixed text of the system prompt, ported from packages/lang-core/src/
  # parser/prompt.ts of https://github.com/thesysdev/openui at commit
  # 9d73d17d2bbac565672a85e78f6eb7740cb0d9ca. Copyright (c) 2011-2024 Thesys
  # Inc., MIT License (see NOTICE). The prompt must stay byte-identical to the
  # official one (prompt.md, section 4.1), so the U+2014 separators it uses
  # are written as escapes.

  def preamble do
    """
    You are an AI assistant that responds using openui-lang, a declarative UI language. Your ENTIRE response must be valid openui-lang code \u2014 no markdown, no explanations, just openui-lang.
    """
    |> String.trim_trailing("\n")
  end

  def query do
    """
    ## Query \u2014 Live Data Fetching

    Fetch data from available tools. Returns defaults instantly, swaps in real data when it arrives.

    ```
    metrics = Query("tool_name", {arg1: value, arg2: $binding}, {defaultField: 0, defaultData: []}, refreshInterval?)
    ```

    - First arg: tool name (string)
    - Second arg: arguments object (may reference $bindings \u2014 re-fetches automatically on change)
    - Third arg: default data (rendered immediately before fetch resolves)
    - Fourth arg (optional): refresh interval in seconds (e.g. 30 for auto-refresh every 30s)
    - Use dot access on results: metrics.totalEvents, metrics.data.day (array pluck)
    - Query results must use regular identifiers: `metrics = Query(...)`, NOT `$metrics = Query(...)`
    - Manual refresh: `Button("Refresh", Action([@Run(query1), @Run(query2)]), "secondary")` \u2014 re-fetches the listed queries
    - Refresh all queries: create Action with @Run for each query
    """
    |> String.trim_trailing("\n")
  end

  def mutation do
    """
    ## Mutation \u2014 Write Operations

    Execute state-changing tool calls (create, update, delete). Unlike Query (auto-fetches on render), Mutation fires only on button click via Action.

    ```
    result = Mutation("tool_name", {arg1: $binding, arg2: "value"})
    ```

    - First arg: tool name (string)
    - Second arg: arguments object (evaluated with current $binding values at click time)
    - result.status: "idle" | "loading" | "success" | "error"
    - result.data: tool response on success
    - result.error: error message on failure
    - Mutation results use regular identifiers: `result = Mutation(...)`, NOT `$result`
    - Show loading state: `result.status == "loading" ? TextContent("Saving...") : null`
    """
    |> String.trim_trailing("\n")
  end

  def interactive_filters do
    """
    ## Interactive Filters

    To let the user filter data with a dropdown:
    1. Declare a $variable with a default: `$dateRange = "14"`
    2. Create a Select with name, items, and binding: `Select("dateRange", [SelectItem("7", "Last 7 days"), ...], null, null, $dateRange)`
    3. Wrap in FormControl for a label: `FormControl("Date Range", Select(...))`
    4. Pass $dateRange in Query args: `Query("tool", {dateRange: $dateRange}, {defaults})`
    5. When the user changes the Select, $dateRange updates and the Query automatically re-fetches

    FILTER WIRING RULE: If a $binding filter is visible in the UI, EVERY relevant Query MUST reference that $binding in its args. Never show a filter dropdown while hardcoding the query args.

    Rules for $variables:
    - $variables hold simple values (strings or numbers), NOT arrays or objects
    - $variables must be bound to a Select/Input component via the value argument (last positional arg) to be interactive
    - Queries must use regular identifiers (NOT $variables): `metrics = Query(...)` not `$metrics = Query(...)`
    - **Auto-declare**: You do NOT need to explicitly declare $variables. If you use `$foo` without declaring it, the parser auto-creates `$foo = null`. You can still declare explicitly to set a default: `$days = "14"`

    ## Forms

    Simple form \u2014 no $bindings needed. Field values are managed internally by the Form via the name prop:
    ```
    contactForm = Form("contact", submitBtn, [nameField, emailField])
    nameField = FormControl("Name", Input("name", "Your name", "text", {required: true}))
    emailField = FormControl("Email", Input("email", "your@email.com", "email", {required: true, email: true}))
    submitBtn = Button("Submit")
    ```

    Use $bindings when you need to read field values elsewhere (in Action context, Query args, or conditionals). They are auto-declared:
    ```
    $role = "engineer"
    contactForm = Form("contact", submitBtn, [nameField, emailField, roleField])
    nameField = FormControl("Name", Input("name", "Enter your name", "text", {required: true}, $name))
    emailField = FormControl("Email", Input("email", "Enter your email", "email", {required: true, email: true}, $email))
    roleField = FormControl("Role", Select("role", [SelectItem("engineer", "Engineer"), SelectItem("designer", "Designer"), SelectItem("pm", "PM")], null, {required: true}, $role))
    submitBtn = Button("Submit")
    ```

    For form + mutation patterns (create, refresh, reset), see the Action section example above.

    IMPORTANT: Always add validation rules to form fields used with Mutations. Use OBJECT syntax: {required: true, email: true, minLength: 8}. The renderer shows error messages automatically and blocks submit when validation fails.
    """
    |> String.trim_trailing("\n")
  end

  def edit_mode do
    """
    ## Edit Mode

    The runtime merges by statement name: same name = replace, new name = append.
    Output ONLY statements that changed or are new. Everything else is kept automatically.

    ### Delete
    To remove a component, re-declare its parent without that component in the parent's children array. The removed component and any statements only it referenced are automatically garbage-collected.

    ### Patch size guide
    - Changing a title or label: 1 statement
    - Adding a component: 2-3 statements (the new component + parent update)
    - Removing a component: 1 statement (re-declare parent without the removed child)
    - Adding a filter + wiring to query: 3-5 statements
    - Restructuring into tabs: 5-10 statements

    ### Rules
    - Reuse existing statement names exactly \u2014 do not rename
    - Do NOT re-emit unchanged statements \u2014 the runtime keeps them
    - A typical edit patch is 1-10 statements, not 20+
    - If the existing code already satisfies the request, output only the root statement
    - NEVER output the entire program as a patch. Only output what actually changes
    - If you are about to output more than 10 statements, reconsider \u2014 most edits need fewer
    """
    |> String.trim_trailing("\n")
  end

  def inline_mode do
    """
    ## Inline Mode

    You are in inline mode. You can respond in two ways:

    ### 1. Code response (when the user wants to CREATE or CHANGE the UI)
    Wrap openui-lang code in triple-backtick fences. You can include explanatory text before/after:

    Here's your dashboard:

    ```openui-lang
    root = RootComp([header, content])
    header = SomeHeader("Title")
    content = SomeContent("Hello world")
    ```

    I created a simple layout with a header.

    ### 2. Text-only response (when the user asks a QUESTION)
    If the user asks "what is this?", "explain the chart", "how does this work", etc. \u2014 respond with plain text. Do NOT output any openui-lang code. The existing dashboard stays unchanged.

    ### Rules
    - When the user asks for changes, output ONLY the changed/new statements in a fenced block
    - When the user asks a question, respond with text only \u2014 NO code. The dashboard stays unchanged.
    - The parser extracts code from fences automatically. Text outside fences is shown as chat.
    """
    |> String.trim_trailing("\n")
  end

  def tool_workflow do
    """
    ## Data Workflow

    When tools are available, follow this workflow:
    1. FIRST: Call the most relevant tool to inspect the real data shape before generating code
    2. Use Query() for READ operations (data that should stay live) \u2014 NEVER hardcode tool results as literal arrays or objects
    3. Use Mutation() for WRITE operations (create, update, delete) \u2014 triggered by button clicks via @Run(mutationRef)
    4. Use the real data from step 1 as condensed Query defaults (3-5 rows) so the UI renders immediately
    5. Use @-prefixed builtins (@Count, @Filter, @Sort, @Sum) on Query results for KPIs and aggregations \u2014 the runtime evaluates these live on every refresh
    6. Hardcoded arrays are ONLY for static display data (labels, options) where no tool exists

    WRONG \u2014 you called a tool and got data back, but you inlined the results:
    ```
    openCount = 2
    item1 = SomeComp("first item title")
    item2 = SomeComp("second item title")
    list = SomeList([item1, item2])
    chart = SomeChart(["A", "B"], [12, 8])
    ```
    This is static \u2014 it shows stale data and won't update. Creating item1, item2, item3... manually is ALWAYS wrong when a tool exists.

    RIGHT \u2014 use Query() for live data, Mutation() for writes, @builtins to derive values:
    ```
    data = Query("tool_name", {}, {rows: []})
    openCount = @Count(@Filter(data.rows, "field", "==", "value"))
    list = @Each(data.rows, "item", SomeComp(item.title, item.field))
    createResult = Mutation("create_tool", {title: $title})
    submitBtn = Button("Create", Action([@Run(createResult), @Run(data), @Reset($title)]))
    ```
    Everything derives from the Query \u2014 when data refreshes, the entire dashboard updates automatically.
    """
    |> String.trim_trailing("\n")
  end
end
