# Mirror to GitLab and trigger GitLab CI

A GitHub Action that mirrors all commits to GitLab, triggers GitLab CI, and returns the results back to GitHub. 

This action uses active polling to determine whether the GitLab pipeline is finished. This means our GitHub Action will run for the same amount of time as it takes for GitLab CI to finish the pipeline. 

## Example workflow

This is an example of a pipeline that uses this action:

```workflow
name: Mirror and run GitLab CI

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v1
    - name: Mirror + trigger CI
      uses: stenongithub/gitlab-mirror-and-ci-action@0.2.2
      with:
        args: "https://gitlab.com/<namespace>/<repository>"
      env:
        GITLAB_HOSTNAME: "gitlab.com"
        GITLAB_USERNAME: "<your Gitlab username>"
        GITLAB_PASSWORD: ${{ secrets.GITLAB_PASSWORD }} // Generate here: https://gitlab.com/profile/personal_access_tokens
        GITLAB_PROJECT_ID: "<GitLab project ID>"
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} // https://help.github.com/en/articles/virtual-environments-for-github-actions#github_token-secret
        GITHUB_EVENT_NAME: github.event_name
```

Be sure to define the `GITLAB_PASSWORD` secret.

## Changelog

0.2.5 (2020-06-30)
------------------

Untriggered manual stages won't break CI.

0.2.4 (2020-6-12)
-----------

Added url-encoding of branch names when retrieving their CI status
from gitlab.

0.2.3 (2020-05-07)
------------------

Force-push from Github to Gitlab to ignore changes that only
happened in Gitlab and to allow rebasing.

0.2.2 (2020-04-17)
------------------

Print debug information if Gitlab CI doesn't return a Pipeline ID.

0.2.1 (2020-04-16)
------------------

This Github Action will now also return "failure" if the Gitlab CI status
is neither "success" nor "failure".
