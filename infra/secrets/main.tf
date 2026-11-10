# Writes what the other roots mint into the Infisical project and folder that matches who reads it
# (infra/cloud/README.md). Nothing is minted here: infra/cloud/environments/{staging,production} mint through
# modules/credentials (behind manage_credentials) and infra/monitoring makes the DSNs and heartbeat URLs. Each root
# exposes a sensitive `secrets` output and a plain `secret_names` output, keyed by destination: "runtime/<folder>"
# (one folder per Worker), "deploy" or "backups". Names drive for_each, so no sensitive value decides which
# resources exist. A root that has not been applied with its outputs yet contributes nothing.
#
# Run only by a person, from a laptop, never in CI. Values are written with value_wo, so the Infisical provider
# keeps no second copy in state; value_wo_version is derived from the value, so any new value (a rotation in a
# source root, or a deliberate -replace there) is rewritten on the next apply here.

locals {
  backend = {
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

  # A source listed in given_output_sources comes from given_outputs instead of its state (a state with another
  # passphrase; source-outputs.sh reads it with its own). Names and the branch are not secret; values stay sensitive.
  given = {
    for s in var.given_output_sources : s => {
      secret_names       = nonsensitive(try(var.given_outputs[s].secret_names, null))
      planetscale_branch = nonsensitive(try(var.given_outputs[s].planetscale_branch, null))
      secrets            = try(var.given_outputs[s].secrets, {})
    }
  }
  sources = merge({
    for s, d in {
      staging    = data.terraform_remote_state.staging
      production = data.terraform_remote_state.production
      monitoring = data.terraform_remote_state.monitoring
    } : s => d[0].outputs if length(d) > 0
  }, local.given)

  # Which project each source's destination kind goes to. Staging has no backups project; monitoring is production.
  projects = {
    staging = { runtime = var.infisical_project_ids.runtime_staging, deploy = var.infisical_project_ids.deploy_staging }
    production = merge(
      { runtime = var.infisical_project_ids.runtime_prod, deploy = var.infisical_project_ids.deploy_prod },
      var.infisical_project_ids.backups_prod == null ? {} : { backups = var.infisical_project_ids.backups_prod },
    )
    monitoring = merge(
      { runtime = var.infisical_project_ids.runtime_prod },
      var.infisical_project_ids.backups_prod == null ? {} : { backups = var.infisical_project_ids.backups_prod },
    )
  }
  environment_of = { staging = "staging", production = "prod", monitoring = "prod" }

  runtime_folders = var.runtime_folders

  secrets = merge([
    for source, outputs in local.sources : merge([
      for dest, names in coalesce(try(outputs.secret_names, null), {}) : {
        for name in names : "${source}/${dest}/${name}" => {
          source = source
          dest   = dest
          name   = name
          kind   = split("/", dest)[0]
          folder = length(split("/", dest)) > 1 ? split("/", dest)[1] : null
        }
      }
    ]...)
  ]...)

  # Where each secret lands, to refuse two sources writing the same name to the same place.
  targets = [for k, s in local.secrets : "${lookup(local.projects[s.source], s.kind, "none")}/${s.folder == null ? "" : s.folder}/${s.name}"]
}

data "terraform_remote_state" "staging" {
  count   = contains(var.given_output_sources, "staging") ? 0 : 1
  backend = "s3"
  config = merge(local.backend, {
    bucket    = var.state_bucket
    key       = var.state_keys.staging
    endpoints = { s3 = var.state_endpoint }
  })
}

data "terraform_remote_state" "production" {
  count   = contains(var.given_output_sources, "production") ? 0 : 1
  backend = "s3"
  config = merge(local.backend, {
    bucket    = var.state_bucket
    key       = var.state_keys.production
    endpoints = { s3 = var.state_endpoint }
  })
}

data "terraform_remote_state" "monitoring" {
  count   = contains(var.given_output_sources, "monitoring") ? 0 : 1
  backend = "s3"
  config = merge(local.backend, {
    bucket    = var.state_bucket
    key       = var.state_keys.monitoring
    endpoints = { s3 = var.state_endpoint }
  })
}

# Plan-time guards: nothing is written if one fails.
resource "terraform_data" "guards" {
  lifecycle {
    precondition {
      condition     = alltrue([for s in values(local.secrets) : contains(keys(local.projects[s.source]), s.kind)])
      error_message = "A source root has a destination with no project here (staging has no backups project; production has one only when backups_prod is set)."
    }
    precondition {
      condition     = alltrue([for s in values(local.secrets) : s.kind != "runtime" || contains(local.runtime_folders, coalesce(s.folder, "-"))])
      error_message = "A runtime secret names a folder that is not in runtime_folders."
    }
    precondition {
      condition     = length(distinct(local.targets)) == length(local.targets)
      error_message = "Two source roots write the same secret name to the same project and folder."
    }
    precondition {
      condition = (
        try(local.sources.staging.planetscale_branch, null) == null ||
        try(local.sources.staging.planetscale_branch, null) != try(local.sources.production.planetscale_branch, null)
      )
      error_message = "Staging and production mint PlanetScale roles on the same branch. Minted roles reach every database on their branch, so staging needs a branch of its own (infra/cloud/README.md)."
    }
    precondition {
      # The deploy's DATABASE_URL_DIRECT is the migration role, which inherits postgres. Only a source that names the
      # branch its roles are on may write it, so the guard above can see it.
      condition = alltrue([for s in values(local.secrets) :
        !(s.kind == "deploy" && s.name == "DATABASE_URL_DIRECT") || try(local.sources[s.source].planetscale_branch, null) != null
      ])
      error_message = "A source writes the deploy DATABASE_URL_DIRECT (the migration role) without naming its PlanetScale branch."
    }
  }
}

resource "infisical_secret_folder" "runtime" {
  for_each = { for pair in setproduct(["staging", "prod"], local.runtime_folders) : "${pair[0]}/${pair[1]}" => { env = pair[0], folder = pair[1] } }

  name             = each.value.folder
  folder_path      = "/"
  project_id       = each.value.env == "staging" ? var.infisical_project_ids.runtime_staging : var.infisical_project_ids.runtime_prod
  environment_slug = var.infisical_environment_slug
}

resource "infisical_secret" "this" {
  for_each   = local.secrets
  depends_on = [terraform_data.guards]

  name             = each.value.name
  folder_path      = each.value.kind == "runtime" ? infisical_secret_folder.runtime["${local.environment_of[each.value.source]}/${each.value.folder}"].path : "/"
  workspace_id     = local.projects[each.value.source][each.value.kind]
  env_slug         = var.infisical_environment_slug
  value_wo         = local.sources[each.value.source].secrets[each.value.dest][each.value.name]
  value_wo_version = parseint(substr(sha256(local.sources[each.value.source].secrets[each.value.dest][each.value.name]), 0, 12), 16)
}
