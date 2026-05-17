import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const server = new Server(
  { name: "weather", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

// 1. Tell the client what tools exist.
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "get_weather",
      description: "Current weather for a city",
      inputSchema: {
        type: "object",
        properties: { city: { type: "string" } },
        required: ["city"],
      },
    },
  ],
}));

// 2. Handle the actual tool call.
server.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name !== "get_weather") {
    throw new Error(`Unknown tool: ${req.params.name}`);
  }

  const { city } = req.params.arguments as { city: string };
  const res = await fetch(`https://wttr.in/${encodeURIComponent(city)}?format=3`);
  const text = await res.text();
  return { content: [{ type: "text", text }] };
});

// 3. Speak MCP over stdio.
const transport = new StdioServerTransport();
await server.connect(transport);
