# A React app on a Phoenix backend

The same program renders in Phoenix and in a React or React Native app with the official renderer, `@openuidev/react-lang`. The Elixir catalog is the source of truth; the app builds its library from the `library.json` it generates.

`examples/react_app` in this repository is a working version of this guide.

## The backend

Generate the spec in your build and serve it:

```bash
mix openui.gen.spec MyApp.Library --out priv/static/library.json
```

The backend calls the model with `OpenUI.Prompt.generate(MyApp.Library, tools: tools)`, streams the text to the app (server-sent events or chunked HTTP), and answers tool calls at an endpoint such as `POST /tools/:name`. Answer them with the same functions your LiveView `tool_provider` uses, and check the user's authorization in each one.

## The app

Build the library from the spec. Props are positional, so each component takes its prop names from `schema.$defs` in key order; the parser validates against the schema as it is:

```ts
import { createLibrary, defineComponent, markReactive } from "@openuidev/lang-core";
import { z } from "zod/v4";
import spec from "./library.json";
import { renderers } from "./components";

const components = Object.entries(spec.components).map(([name, { signature, description }]) => {
  const bindable = new Set([...signature.matchAll(/(\w+)\??: \$binding</g)].map((m) => m[1]));
  const props = Object.keys(spec.schema.$defs[name].properties ?? {}).map((key) => {
    const schema = z.any();
    if (bindable.has(key)) markReactive(schema);
    return [key, schema];
  });
  return defineComponent({ name, description, props: z.object(Object.fromEntries(props)), component: renderers[name] });
});

export const library = { ...createLibrary({ components, root: spec.root }), toJSONSchema: () => spec.schema };
```

Then render:

```tsx
<Renderer
  response={text}
  library={library}
  isStreaming={streaming}
  toolProvider={{ list_tickets: (args) => fetch("/tools/list_tickets", { method: "POST", body: JSON.stringify(args) }).then((r) => r.json()) }}
  onAction={(event) => send(event)}
  onStateUpdate={(state) => save(state)}
/>
```

## Keeping both sides equal

- Commit `library.json` and run `mix openui.gen.spec ... --check` in CI, so it never drifts from the module and never breaks stored programs.
- Keep the same props in the same order on both sides; only add props at the end.
- The state the React renderer reports (`onStateUpdate`) and the one the LiveView renderer reports (`{:state, state}`) have the same shape, so a message stored by one side reopens on the other.
- `examples/react_app/contract` runs the official parser and this library over the same programs and compares the results in CI.
