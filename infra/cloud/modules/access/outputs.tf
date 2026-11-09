output "url" {
  description = "The host's URL. Behind Access as a whole unless staff_paths is set."
  value       = "https://${var.hostname}"
}

output "staff_url" {
  description = "Where staff sign in: the host, or its first staff path."
  value       = var.staff_paths == null ? "https://${var.hostname}" : "https://${var.hostname}/${try(var.staff_paths[0], "")}"
}

output "staff_application_id" {
  value = cloudflare_zero_trust_access_application.staff.id
}

output "audiences" {
  description = "AUD tags of the applications that forward an Access JWT: staff first, then the machine API. Bypass paths forward none."
  value = concat(
    [cloudflare_zero_trust_access_application.staff.aud],
    cloudflare_zero_trust_access_application.service_tokens[*].aud,
  )
}

output "service_token_client_ids" {
  description = "CF-Access-Client-Id per caller pool. Not secret, but store it next to the secret."
  value       = { for k, t in cloudflare_zero_trust_access_service_token.caller : k => t.client_id }
}

output "service_token_client_secrets" {
  description = "CF-Access-Client-Secret per caller pool. Read once after apply, store in Infisical, never commit."
  value       = { for k, t in cloudflare_zero_trust_access_service_token.caller : k => t.client_secret }
  sensitive   = true
}

output "bypass_application_ids" {
  description = "The application that lets bypass machine paths (signed media links, /healthz) through, or empty when there are none."
  value       = cloudflare_zero_trust_access_application.bypass[*].id
}
