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
    BRANCH=$4
    
    #echo "GITHUB_USERNAME: $GITHUB_USERNAME" 
    #echo "GITHUB_REPO: $GITHUB_REPO"
    #echo "BRANCH: $BRANCH"
    
    
    #API returns latest commit first
    icommit=-1
    while [[ "${approved}" != "0" && "${icommit}" -lt 100 ]]
    do
       icommit=$(($icommit+1))
       #echo "approved: ${approved}"
       #echo "icommit: ${icommit}"
       commitauthor=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" "https://api.github.com/repos/${GITHUB_REPO}/commits?sha=${BRANCH}&per_page=100" | jq ".[$icommit] | {commitauthor: .author.login}" | jq ".commitauthor")
       #echo "commitauthor: ${commitauthor}"
       if [[ $commitauthor == $GITHUB_USERNAME ]]; then approved=0; fi
       sha=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" "https://api.github.com/repos/${GITHUB_REPO}/commits?sha=${BRANCH}&per_page=100" | jq ".[$icommit] | {sha: .sha}" | jq ".sha" | sed "s/\\\"/\\,/g" | sed s/\[,\]//g)
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

##################################################################
branchexists() (
    SOURCE_PAT=$1
    GITHUB_REPO=$2
    BRANCH=$3
    #Check if branch for which push/pr testing is requested, exists
    nbranches=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" "https://api.github.com/repos/${GITHUB_REPO}/branches" | jq length)
    branch_exists=1
    ibranch=-1
    while [[ "${branch_exists}" != "0" && "${ibranch}" -lt "${nbranches}" ]]
    do
       ibranch=$(($ibranch+1))
       temp_branch=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" "https://api.github.com/repos/${GITHUB_REPO}/branches" | jq ".[$ibranch] | {branch: .name}" | jq .branch | sed "s/\\\"/\\,/g" | sed s/\[,\]//g)
       if [[ "${temp_branch}" == "${BRANCH}" ]]; then branch_exists=0; fi
    done
    printf "${branch_exists}"
    if [[ "${branch_exists}" != 0 ]]
    then
       #This error needs to go to MIRROR_REPO and not SOURCE_REPO
       echo "Target branch not found, CI job will exit"
       curl -d '{"state":"failure", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPO}/statuses/${sha}"
       exit 1
    fi
)
##################################################################

##################################################################
prapproval() (
    PR_NUMBER=$1
    GITHUB_USERNAME=$2

    approved=1
    
    #Find the latest commit date and author
    ncommits=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}/commits | jq length)
    ncommits=$(($ncommits - 1))
    commitdate=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}/commits | jq ".[${ncommits}] | {created_at: .commit.author.date}" | jq ".created_at")
    commitauthor=$(curl --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}/commits | jq ".[${ncommits}] | {commit_author: .author.login}" | jq .commit_author)

    if [[ $commitauthor == $GITHUB_USERNAME ]]; then approved=0; printf "${commitdate}"; fi
    
    #If commit author is not approved, check comments
    if [[ ${approved} != "0" ]]
    then
       ncomments=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments | jq length)
       approval_comment=1
       icomment=${ncomments}
       while [[ "${approval_comment}" != "0" && "${icomment}" -gt 0 ]]
       do
          icomment=$(($icomment - 1))
          #check comment for string
          curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments | jq ".[$icomment] | {body: .body}" | grep "triggerstring"
          approval_comment=$?
	  commentdate=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments | jq ".[${icomment}] | {created_at: .created_at}" | jq ".created_at")
          #if string matches check if commenter belongs to the pre-approved list and the comment is newer than the latest commit
          if [ "${approval_comment}" = "0" && ${commentdate} > ${commitdate} ]
          then
             commentauthor=$(curl -H "Authorization: token ${SOURCE_PAT}" --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments | jq ".[$icomment] | {commenter: .user.login}" | jq ".commenter")
	     if [[ $commentauthor == $GITHUB_USERNAME ]]; then approved=0; printf "${commentdate}"; fi
             approval_comment=$?
          fi
       done
    fi

)
##################################################################

preapproved=1
DEFAULT_POLL_TIMEOUT=10
POLL_TIMEOUT=${POLL_TIMEOUT:-$DEFAULT_POLL_TIMEOUT}

echo "CI job triggered by event- $REPO_EVENT_TYPE"
#Check if REPO_EVENT_TYPE specified above is supported
if [[ ${REPO_EVENT_TYPE} != "push" && ${REPO_EVENT_TYPE} != "internal_pr" && ${REPO_EVENT_TYPE} != "fork_pr"  ]]
then
   echo "Only PR and Push testing are currently supported. CI will exit"
   exit 1
fi


#Retrieve Github username of SOURCE_PAT
GITHUB_USERNAME=$(curl -H "Authorization: token ${SOURCE_PAT}" -H "Accept: application/vnd.github.v3+json" --silent https://api.github.com/user | jq .login) 
echo "GITHUB_USERNAME: $GITHUB_USERNAME"


#Identify required variables for each type of even and add checks to see if they are empty
#In push there is no target branch
if [[ "${REPO_EVENT_TYPE}" == "push" ]]; then TARGET_BRANCH=${BRANCH}; fi
branchfound="$(branchexists ${SOURCE_PAT} ${GITHUB_REPO} ${TARGET_BRANCH})"

if [[ ${branchfound} != "0" ]]
then
   echo "Branch ${TARGET_BRANCH} not found in the repo, CI job will exit"
   exit 1
fi

#If PR Number is specified use that or else find the latest acceptable PR
if [[ "${REPO_EVENT_TYPE}" = "internal_pr" || "${REPO_EVENT_TYPE}" = "fork_pr" ]]
then
   #number of open pr's
   npr=$(curl --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls | jq length)
   if [[ ${npr} == "0" ]]
   then
      echo "No open PRs, CI will exit."
      exit 1
   fi
fi

if [[ $(printenv PR_NUMBER | wc -c) = 0 ]]
then
   # Cycle through all PRs 
   ipr=-1
   while [[ "$ipr" -lt "$(($npr-1))" ]]
   do
      ipr=$(($ipr+1))
      echo "line 174: $ipr"
      target_PR_NUMBER=$(curl --silent -H "Authorization: token ${SOURCE_PAT}" -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls | jq ".[${ipr}] | {PR_NUMBER : .number}" | jq .PR_NUMBER)
      echo "${target_PR_NUMBER}"
      #Approvaltime is used to find the latest approved action, that PR will be targeted by CI.
      #This function only returns PRs where the latest commit is approved. 
      temp_approvaltime="$(prapproval ${target_PR_NUMBER} ${GITHUB_USERNAME})"
      echo "line 178"
      if [[ $(printenv approvedtime | wc -c) = 0 ]]
      then
         approvedtime=${temp_approvaltime}
	 PR_NUMBER=${target_PR_NUMBER}         
      elif [[ ${temp_approvaltime} > ${approvedtime} ]] 
      then 
         approvedtime=${temp_approvaltime}
	 PR_NUMBER=${target_PR_NUMBER}
      fi
   done
else
   # only check the specified PR.
   approvedtime="$(prapproval ${PR_NUMBER} ${GITHUB_USERNAME})"
fi

if [[ "${REPO_EVENT_TYPE}" = "internal_pr" || "${REPO_EVENT_TYPE}" = "fork_pr" ]]
then
   if [[ $(printenv approvedtime | wc -c) = 0 ]]
   then
      echo "No approval associated with the target PR(s). CI job will exit"
      exit 1
   fi
fi

#Allowed events
#There is no need to checkout branches here, it is now done on a specific SHA
if [ "${REPO_EVENT_TYPE}" = "internal_pr" ]
then
   BRANCH=$(curl --silent -H "Authorization: token ${SOURCE_PAT}" -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER} | jq .head.ref | sed "s/\\\"/\\,/g" | sed s/\[,\]//g)
   git checkout "${BRANCH}"
   sha=$(git rev-parse HEAD)
elif [  "${REPO_EVENT_TYPE}" = "push"  ]
then
   git checkout "${BRANCH}"
elif [ "${REPO_EVENT_TYPE}" = "fork_pr" ]
then
   echo "You are running pull request target, make sure your settings are secure, secrets are accessible."
   #Manual change of git
   rm -rf * .*
   fork_repo=$(curl --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER} | jq .head.repo.clone_url)
   fork_repo="${fork_repo:1:${#fork_repo}-2}"
   git clone --quiet ${fork_repo} .
   GITHUB_HEAD_REF=$(curl --silent -H "Accept: application/vnd.github.antiope-preview+json" https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER} | jq .head.ref)
   GITHUB_HEAD_REF="${GITHUB_HEAD_REF:1:${#GITHUB_HEAD_REF}-2}"
   git checkout "${GITHUB_HEAD_REF}"
   BRANCH=external-pr-${PR_NUMBER}
   git branch -m ${BRANCH}
   sha=$(git rev-parse HEAD)
fi

echo "list all branches: $(git branch -a)"
echo "list github_head_ref: $GITHUB_HEAD_REF"
echo "list github_base_ref: $GITHUB_BASE_REF"
echo "list github_ref: $GITHUB_REF"
echo "list github repo: $GITHUB_REPOSITORY"

if [[ "${REPO_EVENT_TYPE}" = "fork_pr" ]]
then
   echo "list fork repo (if pr from fork): ${fork_repo}"
fi


branch="$(git symbolic-ref --short HEAD)"
echo "branch: l107: ${branch}"
branch_uri="$(urlencode ${branch})"
echo "branch: l109: ${branch_uri}"

#Approval section
if [ "${REPO_EVENT_TYPE}" = "push" ]
then
   #Get the latest commit sha on the target gitlab repository
   base_commitsha=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits?ref_name=${BRANCH}" --silent | jq ".[0] | {id: .id}")
   #Run through the recent 100 commits to find the latest than can be cloned
   sha="$(approvedcommitsha ${SOURCE_PAT} ${GITHUB_USERNAME} ${GITHUB_REPO} ${BRANCH})"
   echo "sha: $sha"
   if [[ $sha != "nil" ]]
   then
      #TODO: check if base_commitsha is older than sha before pushing
      preapproved=0
      git checkout $sha
   fi
fi

if [[ "${preapproved}" != "0" && "${REPO_EVENT_TYPE}" = "push" ]]
then
   echo "Commit author ${commitauthor} not associated with repository. Push testing not allowed. CI will exit"
   exit 1
fi
sh -c "git config --global credential.username $GITLAB_USERNAME"
sh -c "git config --global core.askPass /cred-helper.sh"
sh -c "git config --global credential.helper cache"
sh -c "git remote add mirror $*"
sh -c "echo pushing to $BRANCH branch at $(git remote get-url --push mirror)"
#sh -c "git push mirror $branch --force"
sh -c "git push mirror $sha:refs/heads/$BRANCH"
# If the push fails because the target branch is ahead than the push, Pipeline is counted as failed.
push_status=$?
#echo "push_status: $push_status"
if [[ "${push_status}" != "0" ]] 
then
   echo "Unable to push to target repository, job will fail."
   curl -d '{"state":"failure", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPO}/statuses/${sha}"
   exit 1
fi

sleep $POLL_TIMEOUT

pipeline_id=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${BRANCH}" | jq '.last_pipeline.id')

if [ "${pipeline_id}" = "null" ]
then
    echo "pipeline_id is null, so we can't continue."
    echo "Response from https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${BRANCH} was:"
    echo $(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${BRANCH}")
    exit 1
fi

echo "Triggered CI for branch ${BRANCH}"
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
     curl -d '{"state":"pending", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPO}/statuses/${sha}"  > /dev/null 
   fi
done

echo "Pipeline finished with status ${ci_status}"

#Delete remote branch if PR
if [[ "${REPO_EVENT_TYPE}" = "pull_request" || "${REPO_EVENT_TYPE}" = "pull_request_target" ]]
then
   sh -c "git push mirror --delete ${BRANCH}"
fi

#Checkout how this works with fork-prs
if [ "$ci_status" = "success" ]
then 
  curl -d '{"state":"success", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPO}/statuses/${sha}" 
  exit 0
elif [ "$ci_status" = "manual" ] # do not return non-triggered manual builds as a CI failure
then 
  curl -d '{"state":"success", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPO}/statuses/${sha}" 
  exit 0
elif [ "$ci_status" = "failed" ]
then 
  curl -d '{"state":"failure", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPO}/statuses/${sha}" 
  exit 1
else # no return value, so there's no target URL either
  echo "Pipeline ended without a ci_status: https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines/${pipeline_id}"
  curl -d '{"state":"failure", "context": "gitlab-ci"}' -H "Authorization: token ${SOURCE_PAT}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPO}/statuses/${sha}"
  exit 1
fi
