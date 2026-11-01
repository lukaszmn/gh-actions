#!/usr/bin/env bash
# The DEPLOY_* names are spelled four times: each SSH step's env block in action.yml,
# appleboy's `envs:` list, the OpenSSH stdin loop, and what remote-deploy.sh reads.
# test-remote-deploy.sh keeps its own copy of the names, so it cannot see a mismatch
# inside action.yml; this compares the four. Needs python3 + PyYAML.
# Run: bash actions/deploy-docker-compose/tests/test-action-env-lists.sh [action.yml] [remote-deploy.sh]
set -u
dir=$(dirname "$0")/..
ACTION=${1:-$dir/action.yml} REMOTE=${2:-$dir/remote-deploy.sh} python3 - <<'EOF'
import os, re, sys, yaml
action = yaml.safe_load(open(os.environ['ACTION']))
remote = open(os.environ['REMOTE']).read()
steps = {s.get('name'): s for s in action['runs']['steps']}
legacy = steps['Deploy over SSH (host key not verified)']
pinned = steps['Deploy over SSH (host key pinned)']
deploy = lambda env: {k for k in env if k.startswith('DEPLOY_')}
lists = {
    'legacy env block': deploy(legacy['env']),
    'appleboy envs:': set(legacy['with']['envs'].split(',')),
    'pinned env block': deploy(pinned['env']),
    'stdin loop': set(re.search(r'for name in (.*?); do', pinned['run'], re.S).group(1).replace('\\', ' ').split()),
}
want = lists['legacy env block']
fail = False
for name, got in lists.items():
    ok = got == want
    fail |= not ok
    print(('PASS' if ok else 'FAIL'), name, '' if ok else f'missing={sorted(want - got)} extra={sorted(got - want)}')
unread = sorted(n for n in want if n not in remote)
print('PASS remote-deploy.sh reads every name' if not unread else f'FAIL remote-deploy.sh never reads {unread}')
sys.exit(1 if fail or unread else 0)
EOF
