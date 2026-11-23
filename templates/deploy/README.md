# Deploy targets

Production differs per project; the core does not. `compose.prod.yaml` stays platform-neutral:
no published ports, no domains or proxy labels, db -> backup -> migrate -> app ordering. CI rehearses
that core for every target.

A project picks its target in `AGENTS.md`:

```markdown
## Deploy
- target: `dokploy`        # dokploy | portainer
```

When the target is chosen (usually in the first deploy-related task):
1. Replace the `## Production` section of `README.md` with `<target>/README-production.md`, filling in
   `{{APP_SERVICE}}` (the compose service, `service` in `## Komutlar`) and `{{APP_PORT}}` (its container port).
2. Copy any extra files from `<target>/` into the project root, with the same placeholders filled in
   (`portainer/compose.prod.ports.yaml`), and add their variables to `.env.production.example`.
3. Set `- target:` in `AGENTS.md` → `## Deploy`.

| Target | Access | Extra files |
|---|---|---|
| `dokploy` | Dokploy Domains tab → service + container port | none |
| `portainer` | reverse proxy on the host, or the ports overlay | `compose.prod.ports.yaml` (optional) |
