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

##################################################################
#Approved commit sha
approvedcommitsha() (
    approved=1
    SOURCE_PAT=$1
    GITHUB_USERNAME=$2
    GITHUB_REPO=$3
    TARGET_BRANCH=$4
    
    #echo "GITHUB_USERNAME: $GITHUB_USERNAME" 
    #echo "GITHUB_REPO: $GITHUB_REPO"
    #echo "TARGET_BRANCH: $TARGET_BRANCH"
    
    
    #API returns latest commit first
    icommit=-1
    while [[ "${approved}" != "0" && "${icommit}" -lt 100 ]]
    do
       icommit=$(($icommit+1))
       #echo "approved: ${approved}"
       #echo "icommit: ${icommit}"
       commitauthor=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" "https://api.github.com/repos/${GITHUB_REPO}/commits?sha=${TARGET_BRANCH}&per_page=100" | jq ".[$icommit] | {commitauthor: .commit.author.name}" | jq ".commitauthor")
       #echo "commitauthor: ${commitauthor}"
       if [[ $commitauthor == $GITHUB_USERNAME ]]; then approved=0; fi
       sha=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" "https://api.github.com/repos/${GITHUB_REPO}/commits?sha=${TARGET_BRANCH}&per_page=100" | jq ".[$icommit] | {sha: .sha}" | jq ".sha" | sed "s/\\\"/\\,/g" | sed s/\[,\]//g)
       ncomments=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/commits/$sha/comments | jq length)
       icomment=${ncomments}
       while [[ "${approved}" != "0" && "${icomment}" -gt 0 ]]
       do
          icomment=$(($icomment - 1))
          commentauthor=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/commits/$sha/comments | jq ".[$icomment] | {commentauthor: .user.login}" | jq ".commentauthor")
	  if [[ $commentauthor == $GITHUB_USERNAME ]]; then approved=0; fi
       done
    done
    
    if [[ ${approved} == "0" ]]; then printf "$sha"; else printf "nil"; fi
)
##################################################################

preapproved=1
DEFAULT_POLL_TIMEOUT=10
POLL_TIMEOUT=${POLL_TIMEOUT:-$DEFAULT_POLL_TIMEOUT}

echo "CI job triggered by event- $REPO_EVENT_TYPE"

#Identify required variables and add checks to see if they are empty

#Check if target branch exists
nbranches=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" "https://api.github.com/repos/${GITHUB_REPO}/branches" | jq length)
branch_exists=1
ibranch=-1
while [[ "${branch_exists}" != "0" && "${ibranch}" -lt "${nbranches}" ]]
do
   ibranch=$(($ibranch+1))
   temp_branch=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" "https://api.github.com/repos/${GITHUB_REPO}/branches" | jq ".[$ibranch] | {branch: .name}" | jq .branch | sed "s/\\\"/\\,/g" | sed s/\[,\]//g)
   if [[ "${temp_branch}" == "${TARGET_BRANCH}" ]]; then branch_exists=0; fi
done
if [[ "${branch_exists}" != 0 ]]
then
   echo "Target branch not found, CI job will exit"
   curl -d '{"state":"failure", "context": "gitlab-ci"}' -H "Authorization: token ${GITHUB_TOKEN}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${sha}"
   exit 1
fi


#Allowed events
#There is no need to checkout branches here, it is now done on a specific SHA
if [ "${REPO_EVENT_TYPE}" = "pull_request" ]
then
   git checkout "${GITHUB_HEAD_REF}"
elif [  "${REPO_EVENT_TYPE}" = "push"  ]
then
   git checkout "${TARGET_BRANCH}"
elif [ "${REPO_EVENT_TYPE}" = "pull_request_target" ]
then
   echo "You are running pull request target, make sure your settings are secure, secrets are accessible."
   #Manual change of git
   rm -rf * .*
   fork_repo=$(curl -H --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER} | jq .head.repo.clone_url)
   fork_repo="${fork_repo:1:${#fork_repo}-2}"
   git clone --quiet ${fork_repo} .
   GITHUB_HEAD_REF=$(curl -H --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER} | jq .head.ref)
   GITHUB_HEAD_REF="${GITHUB_HEAD_REF:1:${#GITHUB_HEAD_REF}-2}"
   git checkout "${GITHUB_HEAD_REF}"
   git branch -m external-pr-${PR_NUMBER}
else
   echo "Only PR and Push testing are currently supported. CI will exit"
   exit 1
fi

echo "list all branches: $(git branch -a)"
echo "list github_head_ref: $GITHUB_HEAD_REF"
echo "list github_base_ref: $GITHUB_BASE_REF"
echo "list github_ref: $GITHUB_REF"
echo "list github repo: $GITHUB_REPOSITORY"

if [[ "${REPO_EVENT_TYPE}" = "pull_request_target" ]]
then
   echo "list fork repo (if pr from fork): ${fork_repo}"
fi



#Retrieve Github username of SOURCE_PAT
GITHUB_USERNAME=$(curl -H "Authorization: token ${SOURCE_PAT}" -H "Accept: application/vnd.github.v3+json" --silent https://api.github.com/user | jq .login) 
echo "GITHUB_USERNAME: $GITHUB_USERNAME"


branch="$(git symbolic-ref --short HEAD)"
echo "branch: l107: ${branch}"
branch_uri="$(urlencode ${branch})"
echo "branch: l109: ${branch_uri}"

#Approval section
if [ "${REPO_EVENT_TYPE}" = "push" ]
then
   #Get the latest commit sha on the target gitlab repository
   base_commitsha=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits?ref_name=${TARGET_BRANCH}" --silent | jq ".[0] | {id: .id}")
   #Run through the recent 100 commits to find the latest than can be cloned
   sha="$(approvedcommitsha ${SOURCE_PAT} ${GITHUB_USERNAME} ${GITHUB_REPO} ${TARGET_BRANCH})"
   echo "sha: $sha"
   if [[ $sha != "nil" ]]
   then
      #AK: check if base_commitsha is older than sha before pushing
      preapproved=0
      git checkout $sha
   fi
else
   echo "PR_NUMBER $PR_NUMBER"
   commitauthor=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER} | jq ".user.login")
fi

#echo "commitauthor ${commitauthor}"
#echo "github pre-approved usernames"
#cat /tmp/github_usernames

#grep "$commitauthor" /tmp/github_usernames
#preapproved=$?
#echo "preapproved ${preapproved}"
if [[ "${preapproved}" != "0" && "${REPO_EVENT_TYPE}" = "push" ]]
then
   echo "Commit author ${commitauthor} not associated with repository. Push testing not allowed. CI will exit"
   exit 1
fi

#check if someone from the pre-approved user list has commented with the triggerstring
if [[ "${preapproved}" != "0" ]] && [[ "${REPO_EVENT_TYPE}" = "pull_request" || "${REPO_EVENT_TYPE}" = "pull_request_target" ]]
then
   
   #Comment check route
   #number of comments
   curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments | jq length
   echo "PR_NUMBER ${PR_NUMBER}"
   ncomments=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments | jq length)
   echo "ncomments ${ncomments}"
   if [[ "${ncomments}" = "0" ]]
   then
      echo "Commit author not in trusted list and no approval comment. CI will exit"
      exit 1 
   fi
   approval_comment=1
   icomment=${ncomments}
   while [[ "${approval_comment}" != "0" && "${icomment}" -gt 0 ]]
   do
      icomment=$(($icomment - 1))
      echo "icomment $icomment"
      #check comment for string
      curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments | jq ".[$icomment] | {body: .body}" | grep "triggerstring"
      approval_comment=$?
      #if string matches check if commenter belongs to the pre-approved list
      if [ "${approval_comment}" = "0" ]
      then
         commentauthor=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments | jq ".[$icomment] | {commenter: .user.login}" | jq ".commenter")
         grep "$commentauthor" /tmp/github_usernames
         approval_comment=$?
      fi
   done
   

   #found the latest approval comment, run CI if commit is from earlier time than comment creation
   if [ "${approval_comment}" != "0" ]
   then
      echo "Commit author ${commitauthor} not associated with repository, owner(s) of repo need to comment to run CI. CI will exit"
      exit 1
   fi

   #Label check route
   #entries associated with labels
   nlabels=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/timeline | jq length)
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
      curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/timeline | jq ".[$ilabel] | {event: .event}" | jq ".event" | grep \"labeled\"
      approval_label=$?
      if [ "${approval_label}" = "0" ]
      then
         curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/timeline | jq ".[$ilabel] | {labelname: .label.name}" | jq ".labelname" | grep \"triggerlabel\"
	 approval_label=$?
	 if [ "${approval_label}" = "0" ]
	 then
	    labelauthor=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/timeline | jq ".[$ilabel] | {labelauthor: .actor.login}" | jq ".labelauthor")
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
   
   ncommits=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}/commits | jq length)
   ncommits=$(($ncommits - 1))
   commit_date=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}/commits | jq ".[${ncommits}] | {created_at: .commit.author.date}" | jq ".created_at")
   echo "commit_date $commit_date"
   
   if [[ "${icomment}" -ge 0 ]] 
   then
      comment_date=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments | jq ".[${icomment}] | {created_at: .created_at}" | jq ".created_at")
   fi
   echo "comment_date $comment_date"
   if [[ "${ilabel}" -ge 0 ]] 
   then
      label_date=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.mockingbird-preview" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/timeline | jq ".[${ilabel}] | {created_at: .created_at}" | jq ".created_at")
   fi
   echo "label_date $label_date"

   
   # Dont run CI if comment date is older than commit date
   if [[ "$comment_date" < "$commit_date" && "${icomment}" -ge 0 ]]
   then
      echo "Each new commit requires a new comment to run CI. CI will exit"
      exit 1 
   fi
   # Dont run CI if label add date is older than commit date
   if [[ "${label_date}" < "${commit_date}" && "${ilabel}" -ge 0 ]]
   then
      echo "Each new commit requires (re)adding label to run CI. CI will exit"
      exit 1 
   fi
fi

#Assesing VM security
echo "all running pid"
ps -ef
echo "current dir"
pwd
echo "list files"
ls -la 
echo "add file for persistence"
touch persist
echo "check if it exists"
ls -l persist

sh -c "git config --global credential.username $GITLAB_USERNAME"
sh -c "git config --global core.askPass /cred-helper.sh"
sh -c "git config --global credential.helper cache"
sh -c "git remote add mirror $*"
sh -c "echo pushing to $TARGET_BRANCH branch at $(git remote get-url --push mirror)"
#sh -c "git push mirror $branch --force"
sh -c "git push mirror $sha:refs/heads/$TARGET_BRANCH"
# If the push fails because the target branch is ahead than the push, Pipeline is counted as failed.
push_status=$?
#echo "push_status: $push_status"
if [[ "${push_status}" != "0" ]] 
then
   echo "Unable to push to target repository, job will fail."
   curl -d '{"state":"failure", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${sha}"
   exit 1
fi

sleep $POLL_TIMEOUT

pipeline_id=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${TARGET_BRANCH}" | jq '.last_pipeline.id')

if [ "${pipeline_id}" = "null" ]
then
    echo "pipeline_id is null, so we can't continue."
    echo "Response from https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${TARGET_BRANCH} was:"
    echo $(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${TARGET_BRANCH}")
    exit 1
fi

echo "Triggered CI for branch ${TARGET_BRANCH}"
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
     curl -d '{"state":"pending", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${sha}"  > /dev/null 
   fi
done

echo "Pipeline finished with status ${ci_status}"

#Delete remote branch if PR
if [[ "${REPO_EVENT_TYPE}" = "pull_request" || "${REPO_EVENT_TYPE}" = "pull_request_target" ]]
then
   sh -c "git push mirror --delete ${TARGET_BRANCH}"
fi

if [ "$ci_status" = "success" ]
then 
  curl -d '{"state":"success", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${sha}" 
  exit 0
elif [ "$ci_status" = "manual" ] # do not return non-triggered manual builds as a CI failure
then 
  curl -d '{"state":"success", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${sha}" 
  exit 0
elif [ "$ci_status" = "failed" ]
then 
  curl -d '{"state":"failure", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${sha}" 
  exit 1
else # no return value, so there's no target URL either
  echo "Pipeline ended without a ci_status: https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines/${pipeline_id}"
  curl -d '{"state":"failure", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${sha}"
  exit 1
fi
