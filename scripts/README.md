# scripts/

## test-discovery.sh

Validates that an MCP server correctly implements the OAuth discovery dance — the four things any client (mcp-remote, Claude Desktop, your own agent) needs in order to authenticate.

### What it checks

| Step | Spec | What |
|---|---|---|
| 1 | — | `GET /mcp` returns **401** + `WWW-Authenticate` with a `resource_metadata=` pointer |
| 2 | [RFC 9728](https://datatracker.ietf.org/doc/rfc9728/) | Protected Resource Metadata at `/.well-known/oauth-protected-resource` |
| 3 | [RFC 8414](https://datatracker.ietf.org/doc/rfc8414/) | Authorization Server Metadata at `/.well-known/oauth-authorization-server`, including PKCE S256 support |
| 4 | [RFC 7591](https://datatracker.ietf.org/doc/rfc7591/) | A real client registration via the advertised `registration_endpoint` |

### Run it

```bash
./scripts/test-discovery.sh https://api.your-app.example.com
./scripts/test-discovery.sh https://api.your-app.example.com /mcp   # custom protected path
```

Requires `curl` and `jq` (install with `brew install jq`).

### Output

Green checks for each step that passes, red crosses for what's missing, plus a one-line summary. Exit code is `0` if everything passes — useful for CI.

```
[1/4] Protected resource returns 401 with WWW-Authenticate
  · GET https://api.your-app.com/mcp
  ✓ responds with 401
  ✓ WWW-Authenticate header present
  ✓ resource_metadata URL advertised: https://api.your-app.com/.well-known/oauth-protected-resource

[2/4] RFC 9728 — Protected Resource Metadata
  ...
```

### Common failures

- **No `WWW-Authenticate` header** → mcp-remote silently fails. The empty 401 you're returning is the most common bug.
- **No `registration_endpoint`** → you don't support RFC 7591. Without it, every client needs manual setup.
- **Missing `S256` in `code_challenge_methods_supported`** → mcp-remote won't use your server. PKCE is mandatory.
- **`registration_endpoint` returns 405 / 401** → your registration route exists but isn't actually public. Per RFC 7591, anonymous registration is the default.
