import { defineCloudflareConfig } from "@opennextjs/cloudflare";

// Default config (no R2 incremental cache in v1 — admin pages are
// per-session server renders; a shared cache buys nothing here).
export default defineCloudflareConfig();
