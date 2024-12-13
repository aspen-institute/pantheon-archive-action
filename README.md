# Pantheon Archive Action

## Table of Contents

- [Table of Contents](#table-of-contents)
- [About](#about)
- [Usage](#usage)
- [Example](#example)

## About

This is an action designed to synchronize commits from an outside source (such as Pantheon) into a GitHub repository. It is intended to be used with the [schedule feature](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#onschedule) of Actions to archive projects where developers primarily use other Git repositories as the primary development source but you would like to keep all code in GitHub.

## Usage

```yaml
- uses: aspen-institute/pantheon-archive-action@v1
  with:
    # Repository to check out. Typically looks something like git@example.com:repository.git.
    upstream-repository: ''

    # Branch to synchronize. Pantheon's default is master, but any branch can be synced.
    sync-branch: ''

    # Private SSH key to use to authenticate against the remote. Store this as a GitHub actions secret.
    ssh-key: ''

    # Optional: If the host is not already trusted by your GitHub Actions runner, use this to fetch keys.
    keyscan-host: ''

    # Optional: If using a non-standard port, set it here.
    keyscan-port: ''
```

## Example

This example is a monthly archive of an example Pantheon site.

```yaml
name: Archive Pantheon dev environment

on:
  schedule:
    - cron: '* * 1 * *'

jobs:
  archive:
    name: Archive dev
    runs-on: ubuntu-latest

    steps:
      - uses: aspen-institute/pantheon-archive-action@v1
        with:
          ssh-key: ${{ secrets.SSH_KEY }}

          sync-branch: master

          keyscan-host: codeserver.dev.EXAMPLE.drush.in
          keyscan-port: '2222'

          upstream-repository: codeserver.dev.EXAMPLE@codeserver.dev.EXAMPLE.drush.in:2222/~/repository.git
```
