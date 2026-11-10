mock_provider "cloudflare" {}

variables {
  account_id            = "0123456789abcdef0123456789abcdef"
  name                  = "Test app"
  hostname              = "app.example.com"
  identity_provider_id  = "google-workspace-idp"
  allowed_email_domains = ["example.com"]
}

run "staff_only" {
  command = plan
  assert {
    condition     = cloudflare_zero_trust_access_policy.staff.decision == "allow" && length(cloudflare_zero_trust_access_application.service_tokens) == 0 && length(cloudflare_zero_trust_access_application.bypass) == 0 && length(output.audiences) == 1
    error_message = "Without machine paths there is only the staff application."
  }
  assert {
    condition     = one(cloudflare_zero_trust_access_policy.staff.include).email_domain.domain == "example.com"
    error_message = "Staff access admits the configured domain."
  }
  assert {
    condition     = one(cloudflare_zero_trust_access_policy.staff.require).login_method.id == "google-workspace-idp"
    error_message = "Staff must sign in through the Google Workspace identity provider."
  }
  assert {
    condition     = cloudflare_zero_trust_access_application.staff.allowed_idps == toset(["google-workspace-idp"]) && cloudflare_zero_trust_access_application.staff.domain == "app.example.com"
    error_message = "The whole host offers only the Google Workspace login."
  }
}

run "app_authenticated_paths" {
  command = plan
  variables {
    machine_paths = [
      { path = "api/v1", mode = "bypass" },
      { path = "api/signed-media", mode = "bypass" },
    ]
  }
  assert {
    condition     = cloudflare_zero_trust_access_policy.bypass[0].decision == "bypass" && length(cloudflare_zero_trust_access_application.service_tokens) == 0
    error_message = "Bypass paths get a bypass policy and no service tokens."
  }
  assert {
    condition = toset([for d in cloudflare_zero_trust_access_application.bypass[0].destinations : d.uri]) == toset([
      "app.example.com/api/v1", "app.example.com/api/v1/*",
      "app.example.com/api/signed-media", "app.example.com/api/signed-media/*",
    ])
    error_message = "Bypass covers exactly the listed paths and their subpaths, never the whole host."
  }
}

run "service_token_paths" {
  # Apply against the mock provider so token IDs are known. Mocked IDs repeat
  # across instances, so the check is "only our tokens", not a count.
  command = apply
  variables {
    machine_paths  = [{ path = "mcp", mode = "service_token" }]
    service_tokens = { "claude-code-cloud" = {}, "workers" = { duration = "720h" } }
  }
  assert {
    condition = cloudflare_zero_trust_access_policy.service_tokens[0].decision == "non_identity" && length(cloudflare_zero_trust_access_service_token.caller) == 2 && alltrue([
      for i in cloudflare_zero_trust_access_policy.service_tokens[0].include :
      contains([for t in cloudflare_zero_trust_access_service_token.caller : t.id], i.service_token.token_id)
    ])
    error_message = "The MCP path admits only this application's own service tokens."
  }
  assert {
    condition     = alltrue([for i in cloudflare_zero_trust_access_policy.service_tokens[0].include : i.any_valid_service_token == null && i.everyone == null])
    error_message = "Never admit any valid service token or everyone on a service-token path."
  }
  assert {
    condition     = cloudflare_zero_trust_access_application.service_tokens[0].service_auth_401_redirect && !cloudflare_zero_trust_access_application.service_tokens[0].app_launcher_visible
    error_message = "Machines get a 401, not a login page."
  }
  assert {
    condition     = cloudflare_zero_trust_access_service_token.caller["workers"].duration == "720h" && length(cloudflare_zero_trust_access_application.bypass) == 0
    error_message = "Token durations pass through; no bypass app."
  }
}

run "mcp_with_managed_oauth" {
  command = apply
  variables {
    machine_paths  = [{ path = "mcp", mode = "service_token" }]
    service_tokens = { "claude-code-cloud" = {} }
    machine_oauth  = { redirect_uris = ["https://claude.ai/api/mcp/auth_callback"] }
  }
  assert {
    condition = [for p in cloudflare_zero_trust_access_application.service_tokens[0].policies : p.id] == [
      cloudflare_zero_trust_access_policy.service_tokens[0].id, cloudflare_zero_trust_access_policy.staff.id,
    ]
    error_message = "Service tokens come first, then staff through the same policy as the browser."
  }
  assert {
    condition = (
      cloudflare_zero_trust_access_application.service_tokens[0].oauth_configuration.enabled &&
      cloudflare_zero_trust_access_application.service_tokens[0].oauth_configuration.dynamic_client_registration.allowed_uris == tolist(["https://claude.ai/api/mcp/auth_callback"]) &&
      cloudflare_zero_trust_access_application.service_tokens[0].oauth_configuration.grant.access_token_lifetime == "15m"
    )
    error_message = "Managed OAuth registers only the listed redirect URIs and issues short-lived tokens."
  }
  assert {
    condition     = cloudflare_zero_trust_access_application.service_tokens[0].allowed_idps == toset(["google-workspace-idp"])
    error_message = "OAuth sign-in offers only the Google Workspace login."
  }
  assert {
    condition     = length(output.audiences) == 2
    error_message = "Both the staff and machine API audiences are output for the app's JWT check."
  }
}

run "oauth_only_mcp" {
  command = plan
  variables {
    machine_paths = [{ path = "mcp", mode = "service_token" }]
    machine_oauth = { redirect_uris = ["https://claude.ai/api/mcp/auth_callback"] }
  }
  assert {
    condition     = length(cloudflare_zero_trust_access_policy.service_tokens) == 0 && length(cloudflare_zero_trust_access_application.service_tokens) == 1
    error_message = "Managed OAuth alone is enough for the machine API, with no empty service-token policy."
  }
}

run "oauth_redirect_must_be_https" {
  command = plan
  variables {
    machine_paths = [{ path = "mcp", mode = "service_token" }]
    machine_oauth = { redirect_uris = ["http://claude.ai/callback"] }
  }
  expect_failures = [var.machine_oauth]
}

run "service_token_path_without_tokens" {
  command = plan
  variables {
    machine_paths = [{ path = "mcp", mode = "service_token" }]
  }
  expect_failures = [cloudflare_zero_trust_access_application.service_tokens]
}

run "unknown_mode" {
  command = plan
  variables {
    machine_paths = [{ path = "api/v1", mode = "public" }]
  }
  expect_failures = [var.machine_paths]
}

run "wildcard_path" {
  command = plan
  variables {
    machine_paths = [{ path = "/api/*", mode = "bypass" }]
  }
  expect_failures = [var.machine_paths]
}

run "staff_paths_leave_the_rest_public" {
  # A public site with a staff area: Access covers only the staff area; the staff MCP path is more specific.
  command = apply
  variables {
    staff_paths    = ["staff"]
    machine_paths  = [{ path = "staff/mcp", mode = "service_token" }]
    service_tokens = { "claude-code-cloud" = {} }
    machine_oauth  = { redirect_uris = ["https://claude.ai/api/mcp/auth_callback"] }
  }
  assert {
    condition = toset([for d in cloudflare_zero_trust_access_application.staff.destinations : d.uri]) == toset([
      "app.example.com/staff", "app.example.com/staff/*",
    ])
    error_message = "The staff application covers exactly the staff paths and their subpaths, never the whole host."
  }
  assert {
    condition = toset([for d in cloudflare_zero_trust_access_application.service_tokens[0].destinations : d.uri]) == toset([
      "app.example.com/staff/mcp", "app.example.com/staff/mcp/*",
    ])
    error_message = "The staff MCP path gets its own machine application."
  }
  assert {
    condition     = output.url == "https://app.example.com" && output.staff_url == "https://app.example.com/staff" && length(output.audiences) == 2
    error_message = "The staff URL points at the staff area, and both audiences are output."
  }
}

run "empty_staff_paths" {
  command = plan
  variables {
    staff_paths = []
  }
  expect_failures = [var.staff_paths]
}

run "extra_hostnames" {
  command = plan
  variables {
    extra_hostnames = ["site.pages.dev", "*.site.pages.dev"]
  }
  assert {
    condition     = length(cloudflare_zero_trust_access_application.staff.destinations) == 3
    error_message = "Extra hostnames move the staff application to destinations: the host plus each extra one."
  }
  assert {
    condition     = toset([for d in cloudflare_zero_trust_access_application.staff.destinations : d.uri]) == toset(["app.example.com", "site.pages.dev", "*.site.pages.dev"])
    error_message = "Each extra hostname is covered as a whole."
  }
}
