import { createLibrary, defineComponent, markReactive } from "@openuidev/lang-core";
import type { ComponentRenderer, Library } from "@openuidev/react-lang";
import * as z from "zod/v4";

type Spec = {
  root: string;
  components: Record<string, { signature: string; description: string }>;
  schema: { $defs: Record<string, { properties?: Record<string, unknown> }> };
};

// Props are positional, so each component takes its prop names from schema.$defs in key
// order. The parser validates against the schema as it is, so every prop is z.any() here.
export function buildLibrary(spec: Spec, renderers: Record<string, ComponentRenderer<any>>): Library {
  const components = Object.entries(spec.components).map(([name, { signature, description }]) => {
    const bindable = new Set([...signature.matchAll(/(\w+)\??: \$binding</g)].map((m) => m[1]));
    const props = Object.keys(spec.schema.$defs[name].properties ?? {}).map((key) => {
      const prop = z.any();
      if (bindable.has(key)) markReactive(prop);
      return [key, prop];
    });
    return defineComponent({
      name,
      description,
      props: z.object(Object.fromEntries(props)),
      component: renderers[name],
    });
  });

  return {
    ...createLibrary({ components, root: spec.root }),
    toJSONSchema: () => spec.schema,
  } as unknown as Library;
}
