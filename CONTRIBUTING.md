# Contributing

Thanks for helping. This file is about changing the template itself. It is not copied into projects made from it.

## What belongs here

The template holds generic infrastructure only: workspace layout, the local and cloud loops, CI, secrets handling and the opt-in features. Product code, real credentials, account IDs and anything tied to one company stay out. If a change only makes sense for your project, make it in your project.

Open an issue before a large change (a new opt-in feature, a different provider, a new workspace) so we can agree on the shape first. Small fixes can go straight to a pull request.

## Making a change

1. Install mise and Docker with Compose v2, then run `mise trust && mise install` and `mise exec -- bun install`.
2. Follow the architecture and code ownership rules in [AGENTS.md](AGENTS.md). They apply to people as well as agents.
3. Run the smallest loop that covers your change, and finish with `mise run verify`. Run `mise run infra:check` for anything under `infra/` and `mise run test:e2e` for anything a browser sees.
4. Fill in the pull request template: what changed, how you checked it, and what you could not check.

## Keeping `template.json` in step

`scripts/create-repo.ts` renames the strings in `template.json`'s `replace` map and shifts the ports in `ports`. Those strings and ports must appear only where they should be renamed. If you add a file that uses them, check that a dry run still renames everything:

```bash
mise exec -- bun scripts/create-repo.ts --slug check-run --dest ../check-run
```

The script exits non-zero if a placeholder or port survives. Delete the `../check-run` folder afterwards.

New template-only files (ones a new project should not inherit) go in `template.json`'s `exclude` list.

## Licence

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
