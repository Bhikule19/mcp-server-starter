# mcp-server-starter

A minimal **Model Context Protocol** server in ~50 lines of TypeScript. Exposes one tool — `get_weather(city)` — that Claude Desktop (or any MCP client) can call.

Companion repo for [this LinkedIn post](#) on building your first MCP server.

---

## What you'll get

After ~3 minutes of setup, you can ask Claude:

> *"What's the weather in Pune right now?"*

…and Claude will call your local server, which hits [wttr.in](https://wttr.in), and stream the answer back.

---

## Quick start

```bash
git clone https://github.com/Bhikule19/mcp-server-starter.git
cd mcp-server-starter
npm install
```

Sanity-check it runs:

```bash
npm start
# (it will hang waiting for stdio input — that's correct. Ctrl+C.)
```

---

## Wire it into Claude Desktop

Open the config file:

- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

Add your server (use the **absolute path** to `server.ts`):

```json
{
  "mcpServers": {
    "weather": {
      "command": "npx",
      "args": [
        "tsx",
        "/absolute/path/to/mcp-server-starter/server.ts"
      ]
    }
  }
}
```

**Fully quit and relaunch** Claude Desktop (⌘Q on macOS — not just close the window). The config is read once at boot.

You should see `weather · 1 tool` in the tools picker.

---

## Try it

In a new chat, ask:

> What's the weather in Tokyo?

Claude will call `get_weather({ city: "Tokyo" })`, your server fetches from wttr.in, and the answer comes back.

---

## Debug it

If the tool doesn't appear:

```bash
# macOS — tail the MCP log
tail -f ~/Library/Logs/Claude/mcp*.log
```

Common gotchas:

- **Relative path in the config** — must be absolute.
- **`npx tsx` not found** — install Node 20+ and make sure `npx` is on PATH.
- **Forgot to fully quit Claude** — ⌘Q, not just close window.

You can also run the official inspector standalone:

```bash
npm run inspect
```

This opens a web UI where you can call your tool directly without Claude.

---

## Make it yours

The whole server is one file: [`server.ts`](./server.ts).

To add your own tool, change three things:

1. The tool name + `inputSchema` in `ListToolsRequestSchema`.
2. The handler body in `CallToolRequestSchema` — replace the `fetch` with your DB query, your API call, your shell command.
3. Bump `name` in the `new Server(...)` constructor so it doesn't collide with this one.

That's it. Same protocol, your handler.

---

## Stack

- [`@modelcontextprotocol/sdk`](https://www.npmjs.com/package/@modelcontextprotocol/sdk) — official MCP TypeScript SDK
- [`tsx`](https://www.npmjs.com/package/tsx) — run TS directly, no build step
- Node 20+

---

## License

MIT — do whatever you want with it.

---

Built by [Abhishek Bhikule](https://www.linkedin.com/in/abhishek-bhikule/). If this saved you an afternoon, a follow on LinkedIn is the nicest thank-you.
