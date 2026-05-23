# commit-file-changes

Stages selected files, creates a commit only when changes exist, and pushes that commit to a target branch.

Main inputs:
- `files`: space-separated paths to stage
- `commit_message`: commit message to use
- `target_branch`: branch to push to
