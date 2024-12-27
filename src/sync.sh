#!/bin/bash

set -euo pipefail

export GIT_PROMPT=0

: "${DEBUG:=}"

if test -n "$DEBUG"; then
  echo "Low-level bash debugging is active"
  set -x
fi

# Configuration sanity checks: the ${foo:?message} syntax throws an error if $foo is not set

: "${UPSTREAM_REPOSITORY:?The required variable \$UPSTREAM_REPOSITORY is not set}"
: "${SYNC_BRANCH:?The required variable \$SYNC_BRANCH is not set}"

# Assign empty defaults here
: "${KEYSCAN_HOST:=}"
: "${KEYSCAN_PORT:=}"

# Handle $SSH_KEY
mkdir -p ~/.ssh
chmod 0700 ~/.ssh

(
  # Prevent echoing the SSH key to the terminal for any reason
  set +x

  : "${SSH_KEY:?The required variable \$SSH_KEY is not set}"

  echo "$SSH_KEY" >~/.ssh/id_rsa
  chmod 0600 ~/.ssh/id_rsa
)

# Prevent inadvertent use of the SSH credentials after this point
unset SSH_KEY

# Ensure that we're in the GitHub checkout - we need to modify the repo's
# settings and it's easier than passing -C to every git command
cd "$GITHUB_WORKSPACE"

if test -n "$KEYSCAN_HOST"; then
  if test -n "$KEYSCAN_PORT"; then
    keyscan_args=(-p "$KEYSCAN_PORT" "$KEYSCAN_HOST")
  else
    keyscan_args=("$KEYSCAN_HOST")
  fi

  echo "Scanning keys for $KEYSCAN_HOST${KEYSCAN_PORT:+:}$KEYSCAN_PORT"
  ssh-keyscan "${keyscan_args[@]}" >>~/.ssh/known_hosts
  chmod 0600 ~/.ssh/known_hosts
fi

echo "Adding upstream $UPSTREAM_REPOSITORY"
git remote add upstream "$UPSTREAM_REPOSITORY"
git fetch upstream "$SYNC_BRANCH"

echo "Pulling remote commits into the workspace"
git checkout -b "$SYNC_BRANCH" --track "upstream/$SYNC_BRANCH"

echo "Pushing remote commits up to GitHub"
if ! git push -u origin "$SYNC_BRANCH"; then
  {
    echo "# :exclamation: Error Summary"
    echo "A remote merge conflict was detected."
    echo ""
    echo "Please review this action's full logs to determine the cause."
  } >"$GITHUB_STEP_SUMMARY"

  exit 1
fi
