# Verification log

A dated record of what was actually checked, newest first. Write what ran and what it showed,
not what should work. Keep the "Still needs a hosted check" list honest.

## Still needs a hosted check

- First staging deploy: `mise run release staging`, then `curl -fsS https://<host>/healthz`
- A signed-out request to the web host redirects to Cloudflare Access

## Log

<!--
### YYYY-MM-DD: <what changed>
- `mise run verify`: pass
- `mise run test:e2e`: 8 passed (desktop, phone)
- Not checked: <anything skipped, and why>
-->
