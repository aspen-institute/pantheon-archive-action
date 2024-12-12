#!/usr/bin/env bats

load test_helper
load git_helper

setup() {
  # Simulates the remote (e.g., Pantheon)
  TEST_UPSTREAM_REPO="$(git_init)"

  # Simulates GitHub.com's copy
  TEST_DOWNSTREAM_REPO="$(git_init --branch archive)"

  # Simulates the actions/checkout-generated GitHub workspace
  TEST_DOWNSTREAM_CHECKOUT="$(git_clone "$TEST_DOWNSTREAM_REPO")"

  # Stubs for generating commits
  export GIT_AUTHOR_NAME="An Author"
  export GIT_AUTHOR_EMAIL="author@test.bats"
  export GIT_COMMITTER_NAME="A Committer"
  export GIT_COMMITTER_EMAIL="comitter@test.bats"

  # Our script uses ~, so create a temporary $HOME that we can destroy during
  # teardown
  TEST_TEMP_HOME="$(temp_make)"

  # Used when the script writes to $GITHUB_STEP_SUMMARY
  TEST_TEMP_SUMMARY="$(temp_make)"

  export GITHUB_STEP_SUMMARY="$TEST_TEMP_SUMMARY/summary"
  export GITHUB_WORKSPACE="$TEST_DOWNSTREAM_CHECKOUT"
  export HOME="$TEST_TEMP_HOME"
}

teardown() {
  git_cleanup "$TEST_UPSTREAM_REPO"
  git_cleanup "$TEST_DOWNSTREAM_REPO"
  git_cleanup "$TEST_DOWNSTREAM_CHECKOUT"

  temp_del "$TEST_TEMP_HOME"
  temp_del "$TEST_TEMP_SUMMARY"
}

@test "config: required upstream repository" {
  export SYNC_BRANCH=branch
  export SSH_KEY=dummy
  # not present: UPSTREAM_REPOSITORY

  run bash "$PWD/src/sync.sh"
  assert_failure

  # Ensure the complaint messagage includes the missing variable name
  assert_output --partial "UPSTREAM_REPOSITORY"
}

@test "config: required sync branch" {
  export UPSTREAM_REPOSITORY=repository
  export SSH_KEY=dummy
  # not present: SYNC_BRANCH

  run bash "$PWD/src/sync.sh"
  assert_failure

  assert_output --partial "SYNC_BRANCH"
}

@test "config: required SSH key" {
  export UPSTREAM_REPOSITORY=repository
  export SYNC_BRANCH=branch
  # not present: SSH_KEY

  run bash "$PWD/src/sync.sh"
  assert_failure

  assert_output --partial "SSH_KEY"
}

# Runs a simple sync, but doesn't really care about what happens: only that $SSH_KEY isn't echoed to the output
@test "sync.sh: debug does not leak SSH_KEY" {
  export UPSTREAM_REPOSITORY="file://$TEST_UPSTREAM_REPO"
  export SYNC_BRANCH=main
  export SSH_KEY="-----BEGIN RSA PRIVATE KEY-----"
  export DEBUG=1

  git_commit "$TEST_UPSTREAM_REPO" foo

  run bash "$PWD/src/sync.sh"
  assert_success

  # If this output leaks, fail
  refute_output "-----BEGIN RSA PRIVATE KEY-----"
}

@test "sync.sh: simple sync (main->main)" {
  export UPSTREAM_REPOSITORY="file://$TEST_UPSTREAM_REPO"
  export SYNC_BRANCH=main
  export SSH_KEY=dummy

  git_commit "$TEST_UPSTREAM_REPO" foo --message "add foo"
  git_commit "$TEST_UPSTREAM_REPO" bar --message "add bar"

  run bash "$PWD/src/sync.sh"
  assert_success

  run git -C "$TEST_UPSTREAM_REPO" log main
  assert_success

  # Assert that the upstream and downstream commit histories match exactly
  upstream_repo_log="$output"

  run git -C "$TEST_DOWNSTREAM_REPO" log main
  assert_success
  assert_output "$upstream_repo_log"

  run git -C "$TEST_DOWNSTREAM_REPO" checkout main
  assert_success

  assert_contents_of_file "$TEST_DOWNSTREAM_REPO/foo" "foo"
  assert_contents_of_file "$TEST_DOWNSTREAM_REPO/bar" "bar"
}

@test "sync.sh: simple sync (main->main; additional commits)" {
  export UPSTREAM_REPOSITORY="file://$TEST_UPSTREAM_REPO"
  export SYNC_BRANCH="main"
  export SSH_KEY=dummy

  git_commit "$TEST_UPSTREAM_REPO" foo --message "add foo"
  git_commit "$TEST_UPSTREAM_REPO" bar --message "add bar"

  run bash "$PWD/src/sync.sh"
  assert_success

  git_commit "$TEST_UPSTREAM_REPO" foo --message "update foo" --contents "updated foo"

  # Simulate another GitHub actions run by destroying and regenerating the checkout
  git_cleanup "$TEST_DOWNSTREAM_CHECKOUT"
  TEST_DOWNSTREAM_CHECKOUT="$(git_clone "$TEST_DOWNSTREAM_REPO")"
  export GITHUB_WORKSPACE="$TEST_DOWNSTREAM_CHECKOUT"

  run bash "$PWD/src/sync.sh"
  assert_success

  run git -C "$TEST_UPSTREAM_REPO" log main
  assert_success

  upstream_repo_log="$output"

  run git -C "$TEST_DOWNSTREAM_REPO" log main
  assert_success
  assert_output "$upstream_repo_log"

  run git -C "$TEST_DOWNSTREAM_REPO" checkout main
  assert_success

  assert_contents_of_file "$TEST_DOWNSTREAM_REPO/foo" "updated foo"
  assert_contents_of_file "$TEST_DOWNSTREAM_REPO/bar" "bar"
}

@test "sync.sh: keyscan host" {
  export UPSTREAM_REPOSITORY="file://$TEST_UPSTREAM_REPO"
  export SYNC_BRANCH=main
  export SSH_KEY=dummy

  export KEYSCAN_HOST=remote.domain

  stub ssh-keyscan \
    'remote.domain : true'

  git_commit "$TEST_UPSTREAM_REPO" foo --message "add foo"
  git_commit "$TEST_UPSTREAM_REPO" bar --message "add bar"

  run bash "$PWD/src/sync.sh"
  assert_success

  run git -C "$TEST_UPSTREAM_REPO" log main --format=oneline
  assert_success

  source_repo_log="$output"

  run git -C "$TEST_DOWNSTREAM_REPO" log main --format=oneline
  assert_success
  assert_output "$source_repo_log"

  unstub ssh-keyscan
}

@test "sync.sh: keyscan host+port" {
  export UPSTREAM_REPOSITORY="file://$TEST_UPSTREAM_REPO"
  export SYNC_BRANCH=main
  export SSH_KEY=dummy

  export KEYSCAN_HOST=remote.domain
  export KEYSCAN_PORT=1234

  stub ssh-keyscan \
    '-p 1234 remote.domain : true'

  git_commit "$TEST_UPSTREAM_REPO" foo --message "add foo"
  git_commit "$TEST_UPSTREAM_REPO" bar --message "add bar"

  run bash "$PWD/src/sync.sh"
  assert_success

  run git -C "$TEST_UPSTREAM_REPO" log main --format=oneline
  assert_success

  source_repo_log="$output"

  run git -C "$TEST_DOWNSTREAM_REPO" log main --format=oneline
  assert_success
  assert_output "$source_repo_log"

  unstub ssh-keyscan
}

@test "sync.sh: merge conflict" {
  export UPSTREAM_REPOSITORY="file://$TEST_UPSTREAM_REPO"
  export SYNC_BRANCH=main
  export SSH_KEY=dummy

  export DEBUG=1

  git_commit "$TEST_UPSTREAM_REPO" foo --contents "upstream foo"

  # Make sure the archive branch exists by creating a commit
  git_commit "$TEST_DOWNSTREAM_REPO" archive

  run bash "$PWD/src/sync.sh"
  assert_success

  git_commit "$TEST_UPSTREAM_REPO" foo --contents "upstream foo + modifications"

  # Switch to main and introduce a conflicting change
  run git -C "$TEST_DOWNSTREAM_REPO" checkout main
  assert_success

  git_commit "$TEST_DOWNSTREAM_REPO" foo --contents "downstream foo"

  # Switch to the archive branch here to avoid adding flags to git_clone
  run git -C "$TEST_DOWNSTREAM_REPO" checkout archive
  assert_success

  git_cleanup "$TEST_DOWNSTREAM_CHECKOUT"
  TEST_DOWNSTREAM_CHECKOUT="$(git_clone "$TEST_DOWNSTREAM_REPO")"
  export GITHUB_WORKSPACE="$TEST_DOWNSTREAM_CHECKOUT"

  run bash "$PWD/src/sync.sh"
  assert_failure
  assert_file_contains "$GITHUB_STEP_SUMMARY" 'remote merge conflict' grep
}

@test "sync.sh: dev->dev; ignores main commits" {
  export UPSTREAM_REPOSITORY="file://$TEST_UPSTREAM_REPO"
  export SYNC_BRANCH=dev
  export SSH_KEY=dummy

  git_commit "$TEST_UPSTREAM_REPO" foo --contents "main foo"

  run git -C "$TEST_UPSTREAM_REPO" checkout -b dev
  assert_success

  git_commit "$TEST_UPSTREAM_REPO" foo --contents "dev foo"

  run bash "$PWD/src/sync.sh"

  run git -C "$TEST_UPSTREAM_REPO" log dev --format=oneline
  assert_success

  source_repo_log="$output"

  run git -C "$TEST_DOWNSTREAM_REPO" log dev --format=oneline
  assert_success
  assert_output "$source_repo_log"

  run test -f "$TEST_DOWNSTREAM_REPO/refs/heads/main"
  assert_failure
}

@test "sync.sh: dev->dev; main is not updated" {
  export UPSTREAM_REPOSITORY="file://$TEST_UPSTREAM_REPO"
  export SYNC_BRANCH=dev
  export SSH_KEY=dummy

  git_commit "$TEST_UPSTREAM_REPO" foo --contents "main foo"

  run env SYNC_BRANCH=main bash "$PWD/src/sync.sh"
  assert_success

  run git -C "$TEST_UPSTREAM_REPO" checkout -b dev
  assert_success

  git_commit "$TEST_UPSTREAM_REPO" foo --contents "dev foo"

  git_cleanup "$TEST_DOWNSTREAM_CHECKOUT"
  TEST_DOWNSTREAM_CHECKOUT="$(git_clone "$TEST_DOWNSTREAM_REPO")"
  export GITHUB_WORKSPACE="$TEST_DOWNSTREAM_CHECKOUT"

  run bash "$PWD/src/sync.sh"
  assert_success

  last_seen_main_commit="$(cat "$TEST_UPSTREAM_REPO/.git/refs/heads/main")"

  run git -C "$TEST_UPSTREAM_REPO" checkout main
  assert_success

  git_commit "$TEST_UPSTREAM_REPO" foo --contents "main foo: updated"

  last_main_commit="$(cat "$TEST_UPSTREAM_REPO/.git/refs/heads/main")"

  git -C "$TEST_UPSTREAM_REPO" checkout dev
  git_commit "$TEST_UPSTREAM_REPO" foo --contents "dev foo: updated"
  git_commit "$TEST_UPSTREAM_REPO" bar

  # Simulate another GitHub actions run by destroying and regenerating the checkout
  git_cleanup "$TEST_DOWNSTREAM_CHECKOUT"
  TEST_DOWNSTREAM_CHECKOUT="$(git_clone "$TEST_DOWNSTREAM_REPO")"
  export GITHUB_WORKSPACE="$TEST_DOWNSTREAM_CHECKOUT"

  run bash "$PWD/src/sync.sh"
  assert_success

  run git -C "$TEST_UPSTREAM_REPO" log dev --format=oneline
  assert_success

  source_repo_log="$output"

  run git -C "$TEST_DOWNSTREAM_REPO" log dev --format=oneline
  assert_success
  assert_output "$source_repo_log"

  run git -C "$TEST_DOWNSTREAM_REPO" checkout main
  assert_success

  assert_contents_of_file "$TEST_DOWNSTREAM_REPO/foo" "main foo"
  run test -f "$TEST_DOWNSTREAM_REPO/bar"
  assert_failure

  run git -C "$TEST_DOWNSTREAM_REPO" log main --format=oneline
  assert_output --partial "$last_seen_main_commit"
  refute_output --partial "$last_main_commit"
}
