const createTicket = {
  name: "createTicket",
  description: "Creates a support ticket",
  inputSchema: {
    type: "object",
    properties: {
      title: { type: "string" },
      priority: { type: "string", enum: ["low", "high"] },
    },
    required: ["title"],
  },
  outputSchema: { type: "object", properties: { id: { type: "number" } } },
  annotations: { readOnlyHint: false, destructiveHint: false },
};

const extras = {
  preamble: "You build support dashboards.",
  examples: ['root = Stack([Text("Hi")])'],
  toolExamples: ['tickets = Query("listTickets", {}, {rows: []})'],
  additionalRules: ["Keep labels short.", "Never invent numbers."],
};

export const cases = [
  { name: "fixtures-default", library: "fixtures", options: {} },
  { name: "fixtures-tools", library: "fixtures", options: { tools: ["listTickets", createTicket] } },
  { name: "fixtures-bindings", library: "fixtures", options: { bindings: true } },
  { name: "fixtures-builtins", library: "fixtures", options: { builtinFunctions: true } },
  { name: "fixtures-edit-inline", library: "fixtures", options: { editMode: true, inlineMode: true } },
  { name: "fixtures-extras", library: "fixtures", options: extras },
  { name: "example-default", library: "example", options: {} },
  {
    name: "example-all",
    library: "example",
    options: {
      tools: ["listTickets", createTicket],
      editMode: true,
      inlineMode: true,
      builtinFunctions: true,
      ...extras,
    },
  },
];
