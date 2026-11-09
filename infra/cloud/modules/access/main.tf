# One hostname behind Cloudflare Access: staff sign in through the Google
# Workspace identity provider, and named machine paths get their own, more
# specific Access applications (Access applies the most specific path).
# By default the staff application covers the whole host; with staff_paths it
# covers only those paths and the rest of the host is public.
# The machine API application can also act as an OAuth server (Managed OAuth),
# so MCP clients that cannot send headers sign people in through Access.

locals {
  # A single whole host uses `domain`; paths or extra hostnames need `destinations`.
  staff_destinations = var.staff_paths != null ? flatten([
    for p in var.staff_paths : [
      { type = "public", uri = "${var.hostname}/${p}" },
      { type = "public", uri = "${var.hostname}/${p}/*" },
    ]
    ]) : length(var.extra_hostnames) > 0 ? [
    for h in concat([var.hostname], var.extra_hostnames) : { type = "public", uri = h }
  ] : null
  token_paths  = [for p in var.machine_paths : p.path if p.mode == "service_token"]
  bypass_paths = [for p in var.machine_paths : p.path if p.mode == "bypass"]
  # A path covers its subpaths; the wildcard entry makes that explicit.
  token_destinations = flatten([
    for p in local.token_paths : [
      { type = "public", uri = "${var.hostname}/${p}" },
      { type = "public", uri = "${var.hostname}/${p}/*" },
    ]
  ])
  bypass_destinations = flatten([
    for p in local.bypass_paths : [
      { type = "public", uri = "${var.hostname}/${p}" },
      { type = "public", uri = "${var.hostname}/${p}/*" },
    ]
  ])
}

resource "cloudflare_zero_trust_access_policy" "staff" {
  account_id = var.account_id
  name       = "${var.name}: staff"
  decision   = "allow"
  include = concat(
    [for d in var.allowed_email_domains : { email_domain = { domain = d } }],
    [for e in var.allowed_emails : { email = { email = e } }],
  )
  # Matching the domain is not enough: the identity must come from Google Workspace.
  require          = [{ login_method = { id = var.identity_provider_id } }]
  session_duration = var.session_duration
}

resource "cloudflare_zero_trust_access_application" "staff" {
  account_id                = var.account_id
  name                      = var.name
  type                      = "self_hosted"
  domain                    = local.staff_destinations == null ? var.hostname : null
  destinations              = local.staff_destinations
  session_duration          = var.session_duration
  allowed_idps              = [var.identity_provider_id]
  auto_redirect_to_identity = true
  app_launcher_visible      = true
  policies = [
    { id = cloudflare_zero_trust_access_policy.staff.id, precedence = 1 },
  ]
}

resource "cloudflare_zero_trust_access_service_token" "caller" {
  for_each   = var.service_tokens
  account_id = var.account_id
  name       = "${var.name}: ${each.key}"
  duration   = each.value.duration
}

resource "cloudflare_zero_trust_access_policy" "service_tokens" {
  count      = length(local.token_paths) == 0 || length(var.service_tokens) == 0 ? 0 : 1
  account_id = var.account_id
  name       = "${var.name}: service tokens"
  decision   = "non_identity"
  # Only this application's own tokens, never any_valid_service_token.
  include = [
    for t in cloudflare_zero_trust_access_service_token.caller : { service_token = { token_id = t.id } }
  ]
}

resource "cloudflare_zero_trust_access_application" "service_tokens" {
  count                     = length(local.token_paths) == 0 ? 0 : 1
  account_id                = var.account_id
  name                      = "${var.name}: machine API"
  type                      = "self_hosted"
  destinations              = local.token_destinations
  app_launcher_visible      = false
  service_auth_401_redirect = true
  # Service tokens first; with Managed OAuth, staff signed in through Google as well.
  policies = [
    for i, id in concat(
      cloudflare_zero_trust_access_policy.service_tokens[*].id,
      var.machine_oauth == null ? [] : [cloudflare_zero_trust_access_policy.staff.id],
    ) : { id = id, precedence = i + 1 }
  ]
  allowed_idps = var.machine_oauth == null ? null : [var.identity_provider_id]

  oauth_configuration = var.machine_oauth == null ? null : {
    enabled = true
    dynamic_client_registration = {
      enabled                = true
      allowed_uris           = var.machine_oauth.redirect_uris
      allow_any_on_localhost = var.machine_oauth.allow_loopback
      allow_any_on_loopback  = var.machine_oauth.allow_loopback
    }
    grant = {
      access_token_lifetime = var.machine_oauth.access_token_lifetime
      session_duration      = var.machine_oauth.session_duration
    }
  }

  lifecycle {
    precondition {
      condition     = length(var.service_tokens) > 0 || var.machine_oauth != null
      error_message = "A service_token machine path needs service_tokens, machine_oauth or both."
    }
  }
}

resource "cloudflare_zero_trust_access_policy" "bypass" {
  count      = length(local.bypass_paths) == 0 ? 0 : 1
  account_id = var.account_id
  name       = "${var.name}: app-authenticated paths"
  decision   = "bypass"
  include    = [{ everyone = {} }]
}

resource "cloudflare_zero_trust_access_application" "bypass" {
  count                = length(local.bypass_paths) == 0 ? 0 : 1
  account_id           = var.account_id
  name                 = "${var.name}: app-authenticated paths"
  type                 = "self_hosted"
  destinations         = local.bypass_destinations
  app_launcher_visible = false
  policies = [
    { id = cloudflare_zero_trust_access_policy.bypass[0].id, precedence = 1 },
  ]
}
