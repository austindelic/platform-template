# Security

## Reporting a vulnerability

Please report security problems privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Do not open a public issue.

Include what you found, how to reproduce it, and which files or workflows it affects. You will get a reply within a week.

## Scope

This repository is a template. In scope: anything a project made from it would inherit, such as the Cloudflare Access check in `apps/web`, the GitHub Actions workflows and their OIDC trust, the secrets handling in `scripts/` and `infra/`, and the backup encryption.

Out of scope: projects made from the template (report those to their owners) and vulnerabilities in upstream tools such as Cloudflare, Infisical or OpenTofu (report those upstream).

## For projects made from this template

Before you expose real data, add your own authentication and access policy, replace the example feature, and set up your own security contact. This file is not copied into new projects.
