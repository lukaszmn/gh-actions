# detect-changed-paths

Checks out the repository, calculates changed files for the current ref, and returns a JSON object for any number of named regex checks.

Main inputs:
- `checks_json`: JSON array of named checks

Outputs:
- `results_json`: JSON object for all named checks
- `changed_files`: newline-separated list of changed files

Example `checks_json`:

```json
[
	{"name":"frontend_app","regex":"^client/"},
	{"name":"frontend_admin","regex":"^apps/admin/"},
	{"name":"backend_api","regex":"^src/Structor.Api/"}
]
```

Example workflow usage:

```yaml
jobs:
	detect-changes:
		runs-on: ubuntu-latest
		outputs:
			results_json: ${{ steps.changed-paths.outputs.results_json }}
		steps:
			- id: changed-paths
				uses: ./.github/actions/detect-changed-paths
				with:
					checks_json: |
						[
							{"name":"api","regex":"^(src/|Structor\\.slnx$)"},
							{"name":"nginx","regex":"^client/"}
						]

	build:
		needs: [detect-changes]
		if: fromJSON(needs.detect-changes.outputs.results_json).api
		runs-on: ubuntu-latest
		steps:
			- run: echo Build API image
```

Example `results_json` output:

```json
{"api":true,"nginx":false,"any":true}
```
