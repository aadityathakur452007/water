// Minimal ambient typing for the Cloudflare Workers runtime import used by
// server-only transport code (service bindings reachability). The real env
// shape comes from wrangler.jsonc; server code narrows per binding.
declare module "cloudflare:workers" {
  const env: Record<string, unknown>;
}
