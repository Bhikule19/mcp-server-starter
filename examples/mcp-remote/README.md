# mcp-remote config examples

Two ways to authenticate to a **remote** MCP server from Claude Desktop, using the official [`mcp-remote`](https://www.npmjs.com/package/mcp-remote) bridge.

The local `server.ts` in this repo uses `stdio` transport — Claude spawns it as a subprocess, no auth needed. These examples are for the other case: your MCP server lives on the internet, and multiple machines (or multiple humans) need to talk to it.

---

## 1. Shared API key — [`shared-key.json`](./shared-key.json)

**When this is the right call:**

- You're the only person using the server
- It's a CI/CD job or background service — one identity is the point
- You're prototyping and will harden later
- Everyone using the server has the same role (no per-user scopes)

**Setup:**

1. Copy [`shared-key.json`](./shared-key.json) into `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows).
2. Replace `sk_live_replace_me` with your real API key.
3. Replace the URL with your server's MCP endpoint.
4. Fully quit Claude Desktop (⌘Q) and relaunch.

**On the server side**, you handle auth in the simplest way possible:

```ts
// Whatever framework you use
if (req.headers.get("authorization") !== `Bearer ${process.env.API_KEY}`) {
  return new Response("Unauthorized", { status: 401 });
}
```

That's it. Done.

---

## 2. OAuth discovery — [`oauth.json`](./oauth.json)

**When this is the right call:**

- Multiple humans share the server
- You need an audit trail (SOC 2, HIPAA, internal compliance)
- Permissions differ per user
- You're shipping to third parties
- You'd hate to rotate a single shared key across many machines

**Setup:**

1. Copy [`oauth.json`](./oauth.json) into the same config path as above.
2. Replace only the URL — there's no key.
3. Fully quit Claude Desktop and relaunch.
4. First time you invoke a tool, your browser opens. Log in. Token caches locally under `~/.mcp-auth/`.

**On the server side**, you need to implement:

| Endpoint | Spec | What it does |
|---|---|---|
| `GET /.well-known/oauth-protected-resource` | [RFC 9728](https://datatracker.ietf.org/doc/rfc9728/) | Tells clients which authorization server to use |
| `GET /.well-known/oauth-authorization-server` | [RFC 8414](https://datatracker.ietf.org/doc/rfc8414/) | Advertises the OAuth endpoints (authorize, token, register) |
| `POST /register` | [RFC 7591](https://datatracker.ietf.org/doc/rfc7591/) | Dynamic Client Registration — `mcp-remote` calls this first |
| `GET /authorize` + `POST /token` | RFC 6749 + PKCE | Standard authorization code flow with **S256** challenge |

And the bit that triggers the whole dance: on any unauthenticated request to your MCP endpoint, respond with `401` **plus** a `WWW-Authenticate` header pointing at the resource metadata:

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer resource_metadata="https://api.your-app.example.com/.well-known/oauth-protected-resource"
```

That `WWW-Authenticate` header is what makes the magic happen — without it, `mcp-remote` won't know to start the OAuth flow.

---

## How to choose, in one line

> **Default to shared keys. Switch to OAuth the moment a second human touches the server.**

---

## Debugging

- `mcp-remote` logs to `~/.mcp-auth/` and stderr — check Claude's MCP logs at `~/Library/Logs/Claude/mcp*.log`
- Clear cached OAuth tokens: `rm -rf ~/.mcp-auth/`
- Test discovery manually: `curl -i https://api.your-app.example.com/mcp` — you should see the `WWW-Authenticate` header in the 401 response

---

Companion to [this LinkedIn post](#) on choosing between the two patterns.
