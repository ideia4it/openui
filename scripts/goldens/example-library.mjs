// The example catalog of test/support/example_library.ex, built with the
// official library so its LibrarySpec and prompts are the reference.
import { z } from "zod/v4";
import {
  action,
  createLibrary,
  defineAction,
  defineComponent,
  defineFunction,
  markReactive,
  steps,
} from "@openuidev/lang-core";

// A slot that takes any catalog component. Zod cannot name every component
// without recursion, so the schema is written as `any` here and rewritten to
// an anyOf of every component below, as the conformance library.json does.
const anyComponents = () => z.array(z.any());

const bound = (schema) => {
  markReactive(schema);
  return schema;
};

const component = (name, description, props) =>
  defineComponent({ name, description, props: z.object(props), component: null });

export const CopyToClipboard = defineAction({
  name: "CopyToClipboard",
  description: "Copies text to the clipboard",
  params: z.object({ text: z.string() }),
});

const Percent = defineFunction({
  name: "Percent",
  description: "Part over total as a percentage string",
  params: z.object({ part: z.number(), total: z.number() }),
  returns: z.string(),
  fn: ({ part, total }) => `${Math.round((part / total) * 100)}%`,
});

const Stack = component("Stack", "Lays out children in a column or a row", {
  children: anyComponents(),
  direction: z.enum(["row", "column"]).optional(),
});
const Card = component("Card", "A titled container", {
  title: z.string(),
  children: anyComponents().optional(),
});
const Text = component("Text", "A run of text", {
  text: z.string(),
  variant: z.enum(["body", "heading"]).default("body"),
});
const Metric = component("Metric", "A labeled number with an optional trend", {
  label: z.string(),
  value: z.number(),
  trend: z
    .object({ direction: z.enum(["up", "down"]), percent: z.number().optional() })
    .optional(),
});
const Series = component("Series", "One line of a LineChart", {
  name: z.string(),
  values: z.array(z.number()),
});
const LineChart = component("LineChart", "Time series, daily or monthly", {
  labels: z.array(z.string()),
  series: z.array(Series.ref),
});
const Col = component("Col", "One table column: a header and its cell values", {
  label: z.string(),
  data: z.array(z.any()).optional(),
});
const Table = component("Table", "A table built from columns", {
  columns: z.array(Col.ref),
});
const Button = component("Button", "A clickable button", {
  label: z.string(),
  action: action().optional(),
  variant: z.enum(["primary", "secondary"]).optional(),
  share: z.union([CopyToClipboard.ref, steps.OpenUrl.ref]).optional(),
});
const Form = component("Form", "Groups its inputs under a form name", {
  name: z.string(),
  children: anyComponents(),
});
const Input = component("Input", "A text field", {
  name: z.string(),
  placeholder: z.string().optional(),
  value: bound(z.string().optional()),
  rules: z.object({}).optional(),
});
const SelectItem = component("SelectItem", "One option of a Select", {
  value: z.string(),
  label: z.string(),
});
const Select = component("Select", "A dropdown", {
  name: z.string(),
  items: z.array(SelectItem.ref),
  value: bound(z.string().optional()),
});
const Highlight = component("Highlight", "A card or a metric to call attention to", {
  content: z.union([Card.ref, Metric.ref]),
  enabled: z.boolean().optional(),
});

const components = [
  Stack,
  Card,
  Text,
  Metric,
  LineChart,
  Series,
  Table,
  Col,
  Button,
  Form,
  Input,
  Select,
  SelectItem,
  Highlight,
];

const library = createLibrary({
  id: "example",
  root: "Stack",
  components,
  functions: [Percent],
  actions: [CopyToClipboard],
  componentGroups: [
    { name: "Layout", components: ["Stack", "Card"] },
    {
      name: "Charts",
      components: ["LineChart", "Series"],
      notes: ["Prefer a chart over a table for series."],
    },
    { name: "Forms", components: ["Form", "Input", "Select", "SelectItem", "Button"] },
  ],
});

function withComponentSlots(spec) {
  const anyOf = components.map(({ name }) => ({ $ref: `#/$defs/${name}` }));
  for (const [name, prop] of [
    ["Stack", "children"],
    ["Card", "children"],
    ["Form", "children"],
  ]) {
    spec.schema.$defs[name].properties[prop].items = { anyOf };
  }
  return spec;
}

// A host that versions its library adds `version` (prompt.md, section 2.1).
export const exampleSpec = { ...withComponentSlots(library.toSpec()), version: "1.0.0" };
