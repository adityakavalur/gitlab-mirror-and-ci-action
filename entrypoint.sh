#!/bin/sh

set -u
##################################################################
urlencode() (
    i=1
    max_i=${#1}
    while test $i -le $max_i; do
        c="$(expr substr $1 $i 1)"
        case $c in
            [a-zA-Z0-9.~_-])
		printf "$c" ;;
            *)
		printf '%%%02X' "'$c" ;;
        esac
        i=$(( i + 1 ))
    done
)

##################################################################
DEFAULT_POLL_TIMEOUT=30
POLL_TIMEOUT=${POLL_TIMEOUT:-$DEFAULT_POLL_TIMEOUT}

## check if this was a tag push and react accordingly

if [ "${GITHUB_REF::11}" = "refs/heads/" ]
then
  git checkout "${GITHUB_REF:11}"
  branch="$(git symbolic-ref --short HEAD)"
  branch_uri="$(urlencode ${branch})"
  pipeline_id=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${branch_uri}" | jq '.last_pipeline.id')
else
  echo $GITHUB_REF
  branch_contains="$(git branch -a --contains ${GITHUB_REF:5})" # which branches have this tag?
  echo "branch_contains:" $branch_contains
  branch_origin="${branch_contains#*remotes\/}" # select origin branch
  git checkout "$branch_origin"
  branch="${branch_contains#*remotes\/*/}" # select origin branch excluding "origin"
  echo "branch: "$branch
  branch_uri="$(urlencode ${branch})" # encode branch for URL
  echo "branch_uri:" $branch_uri
  pipeline_id=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/trigger/pipeline?ref=${GITHUB_REF:10}" | jq '.last_pipeline.id')
fi

echo "configuring git"
sh -c "git config --global credential.username $GITLAB_USERNAME"
sh -c "git config --global core.askPass /cred-helper.sh"
sh -c "git config --global credential.helper cache"
echo "adding git remote mirror"
sh -c "git remote add mirror $*"
sh -c "echo pushing to $branch branch at $(git remote get-url --push mirror)"
sh -c "git push mirror $branch --force"

sleep $POLL_TIMEOUT

if [ "${pipeline_id}" = "null" ]
then
    echo "pipeline_id is null, so we can't continue."
    echo "Response from https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${branch_uri} was:"
    echo $(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${branch_uri}")
    exit 1
fi

echo "Triggered CI for branch ${branch}"
echo "Working with pipeline id #${pipeline_id}"
echo "Poll timeout set to ${POLL_TIMEOUT}"

ci_status="pending"

until [[ "$ci_status" != "pending" && "$ci_status" != "running" ]]
do
   sleep $POLL_TIMEOUT
   ci_output=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines/${pipeline_id}")
   ci_status=$(jq -n "$ci_output" | jq -r .status)
   ci_web_url=$(jq -n "$ci_output" | jq -r .web_url)
   
   echo "Current pipeline status: ${ci_status}"
   if [ "$ci_status" = "running" ]
   then
     echo "Checking pipeline status..."
     curl -d '{"state":"pending", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${GITHUB_TOKEN}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}"  > /dev/null 
   fi
done

echo "Pipeline finished with status ${ci_status}"
  
if [ "$ci_status" = "success" ]
then 
  curl -d '{"state":"success", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${GITHUB_TOKEN}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}" 
  exit 0
elif [ "$ci_status" = "manual" ] # do not return non-triggered manual builds as a CI failure
then 
  curl -d '{"state":"success", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${GITHUB_TOKEN}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}" 
  exit 0
elif [ "$ci_status" = "failed" ]
then 
  curl -d '{"state":"failure", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${GITHUB_TOKEN}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}" 
  exit 1
else # no return value, so there's no target URL either
  echo "Pipeline ended without a ci_status: https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines/${pipeline_id}"
  curl -d '{"state":"failure", "context": "gitlab-ci"}' -H "Authorization: token ${GITHUB_TOKEN}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}"
  exit 1
fi
