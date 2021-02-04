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
DEFAULT_POLL_TIMEOUT=10
POLL_TIMEOUT=${POLL_TIMEOUT:-$DEFAULT_POLL_TIMEOUT}

echo "CI job triggered by event- $GITHUB_EVENT_NAME"
echo "list all branches: $(git branch -a)"
echo "list github_head_ref: $GITHUB_HEAD_REF"
echo "list github_base_ref: $GITHUB_BASE_REF"
echo "list github_ref: $GITHUB_REF"
echo "list github repo: $GITHUB_REPOSITORY"

#Allowed events
if [ "${GITHUB_EVENT_NAME}" = "pull_request" ]
then
   git checkout "${GITHUB_HEAD_REF}"
elif [  "${GITHUB_EVENT_NAME}" = "push"  ]
then
   git checkout "${GITHUB_REF:11}"
elif [ "${GITHUB_EVENT_NAME}" = "pull_request_target" ]
then
   echo "You are running pull request target, make sure your settings are secure."
   git checkout "${GITHUB_HEAD_REF}"
else
   echo "Only PR and Push testing are currently supported. CI will exit"
   exit 1
fi



echo "entrypoint: line49"
#list of pre-approved commiters based on whether repo is in username space or organization
touch /dev/null > /tmp/github_usernames
pwd
ls -la /tmp
ls -la .
org_type=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY} | grep type | head -n 1 | awk '{print $2}' | sed "s/\\\"/\\,/g" | sed s/\[,\]//g)
if [ "${org_type}" = "Organization" ]
then
   org_name=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY} | grep login | head -n 1 | awk '{print $2}' | sed "s/\\\"/\\,/g" | sed s/\[,\]//g)
   curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/orgs/${org_name}/members | grep login | head -n 1 | awk '{print $2}' > /tmp/github_usernames
else
   curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY} | grep login | head -n 1 | awk '{print $2}' > /tmp/github_usernames   
fi

echo "entrypoint: line62"
branch="$(git symbolic-ref --short HEAD)"
branch_uri="$(urlencode ${branch})"

#Approval section

if [ "${GITHUB_EVENT_NAME}" = "push" ]
then
   commitauthor=$(git log -n 1 ${branch} | grep Author | awk '{print $2}')
   commitauthor=\"${commitauthor}\"
else
   PR_NUMBER=$(echo $GITHUB_REF | awk 'BEGIN { FS = "/" } ; { print $3 }')
   commitauthor=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER} | jq ".user.login")
fi

echo "commitauthor ${commitauthor}"
echo "github pre-approved usernames"
cat /tmp/github_usernames

grep "$commitauthor" /tmp/github_usernames
preapproved=$?
echo "preapproved ${preapproved}"
if [[ "${preapproved}" != "0" && "${GITHUB_EVENT_NAME}" = "push" ]]
then
   echo "Commit author ${commitauthor} not associated with repository. Push testing not allowed. CI will exit"
   exit 1
fi
echo "entrypoint: line75"
#check if someone from the pre-approved user list has commented with the triggerstring
if [[ "${preapproved}" != "0" && "${GITHUB_EVENT_NAME}" = "pull_request" ]]
then
   PR_NUMBER=$(echo $GITHUB_REF | awk 'BEGIN { FS = "/" } ; { print $3 }')
   
   #Comment check route
   #number of comments
#   curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments
#   curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments | jq length
#   echo "PR_NUMBER ${PR_NUMBER}"
#   ncomments=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments | jq length)
#   echo "ncomments ${ncomments}"
#   if [[ "${ncomments}" = "0" ]]
#   then
#      echo "Commit author not in trusted list and no approval comment. CI will exit"
#      exit 1 
#   fi
#   approval_comment=1
#   icomment=${ncomments}
#   while [[ "${approval_comment}" != "0" && "${icomment}" -gt 0 ]]
#   do
#      icomment=$(($icomment - 1))
#      echo "icomment $icomment"
#      #check comment for string
#      curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments | jq ".[$icomment] | {body: .body}" | grep "triggerstring"
#      approval_comment=$?
#      #if string matches check if commenter belongs to the pre-approved list
#      if [ "${approval_comment}" = "0" ]
#      then
#         commentauthor=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments | jq ".[$icomment] | {commenter: .user.login}" | jq ".commenter")
#         grep "$commentauthor" /tmp/github_usernames
#         approval_comment=$?
#      fi
#   done
#   
#   echo "entrypoint: line100"
#   #found the latest approval comment, run CI if commit is from earlier time than comment creation
#   if [ "${approval_comment}" != "0" ]
#   then
#      echo "Commit author ${commitauthor} not associated with repository, owner(s) of repo need to comment to run CI. CI will exit"
#      exit 1
#   fi
#   echo "icomment ${icomment}"

   #Label check route
   #entries associated with labels
   nlabels=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/timeline | jq length)
   if [[ "${nlabels}" = "0" ]]
   then
      echo "Commit author not in trusted list and no approval label. CI will exit"
      exit 1 
   fi
   approval_label=1
   ilabel=${nlabels}
   while [[ "${approval_label}" != "0" && "${ilabel}" -gt 0 ]]
   do
      ilabel=$(($ilabel - 1))
      curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/timeline | jq ".[$ilabel] | {event: .event}" | jq ".event" | grep \"labeled\"
      approval_label=$?
      if [ "${approval_label}" = "0" ]
      then
         curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/timeline | jq ".[$ilabel] | {labelname: .label.name}" | jq ".labelname" | grep \"triggerlabel\"
	 approval_label=$?
	 if [ "${approval_label}" = "0" ]
	 then
	    labelauthor=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/timeline | jq ".[$ilabel] | {labelauthor: .actor.login}" | jq ".labelauthor")
	    grep "$labelauthor" /tmp/github_usernames
            approval_label=$?
	 fi
      fi
   done
   
   #found the latest approval comment, run CI if commit is from earlier time than comment creation
   if [ "${approval_label}" != "0" ]
   then
      echo "Commit author ${commitauthor} not associated with repository, owner(s) of repo needs to add label to run CI. CI will exit"
      exit 1
   fi
   
   ncommits=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/commits | jq length)
   ncommits=$(($ncommits - 1))
   commit_date=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/commits | jq ".[${ncommits}] | {created_at: .commit.author.date}" | jq ".created_at")
   echo "commit_date $commit_date"
   
#   if [[ "${icomment}" -ge 0 ]] 
#   then
#      comment_date=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments | jq ".[${icomment}] | {created_at: .created_at}" | jq ".created_at")
#   fi
#   echo "comment_date $comment_date"
   if [[ "${ilabel}" -ge 0 ]] 
   then
      label_date=$(curl -H "Authorization: token ${GITHUB_TOKEN}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/timeline | jq ".[${ilabel}] | {created_at: .created_at}" | jq ".created_at")
   fi
   echo "label_date $label_date"

   
#   # Dont run CI if comment date is older than commit date
#   if [[ "$comment_date" > "$commit_date" && "${icomment}" -ge 0 ]]
#   then
#      echo "Each new commit requires a new comment to run CI. CI will exit"
#      exit 1 
#   fi
   # Dont run CI if label add date is older than commit date
   if [[ "${label_date}" > "${commit_date}" && "${ilabel}" -ge 0 ]]
   then
      echo "Each new commit requires (re)adding label to run CI. CI will exit"
      exit 1 
   fi

fi

echo "entrypoint: line117"



sh -c "git config --global credential.username $GITLAB_USERNAME"
sh -c "git config --global core.askPass /cred-helper.sh"
sh -c "git config --global credential.helper cache"
sh -c "git remote add mirror $*"
sh -c "echo pushing to $branch branch at $(git remote get-url --push mirror)"
#sh -c "git push mirror $branch --force"
sh -c "git push mirror $branch"

sleep $POLL_TIMEOUT

pipeline_id=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${branch_uri}" | jq '.last_pipeline.id')
echo "entrypoint: line134"
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
echo "entrypoint: line163"
echo "Pipeline finished with status ${ci_status}"

#Delete remote branch if PR
if [[ "${GITHUB_EVENT_NAME}" = "pull_request" || "${GITHUB_EVENT_NAME}" = "pull_request_target" ]]
then
   sh -c "git push mirror --delete $branch"
fi

echo "entrypoint: line172"  
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
