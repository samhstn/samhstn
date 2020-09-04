#!/bin/bash

STACK=$(aws cloudformation describe-stacks --stack-name "samhstn-${ISSUE_NUMBER}" 2>/dev/null)

if [ $? -eq 0 ]; then
  UPDATE_ERR=$(aws cloudformation update-stack \
    --stack-name "samhstn-${ISSUE_NUMBER}" \
    --template-body file://infra/samhstn/dynamic-build.yml \
    --capabilities CAPABILITY_IAM \
    --parameters "ParameterKey=GithubBranch,ParameterValue=${CODEBUILD_SOURCE_VERSION}" 2>&1)
  if [ $? -eq 0 ]; then
    aws cloudformation wait stack-update-complete \
      --stack-name "samhstn-${ISSUE_NUMBER}"
  elif [[ $UPDATE_ERR =~ "No updates are to be performed" ]]; then
    echo "No updates are to be performed"
  else
    echo "UPDATE_ERR: $UPDATE_ERR"
    exit 1
  fi
else
  aws cloudformation create-stack \
    --stack-name "samhstn-${ISSUE_NUMBER}" \
    --template-body file://infra/samhstn/dynamic-build.yml \
    --capabilities CAPABILITY_IAM \
    --parameters "ParameterKey=GithubBranch,ParameterValue=${CODEBUILD_SOURCE_VERSION}"
  aws cloudformation wait stack-create-complete \
    --stack-name "samhstn-${ISSUE_NUMBER}"
fi

aws deploy create-deployment \
  --application-name "dynamic-samhstn-${ISSUE_NUMBER}" \
  --deployment-group-name "dynamic-samhstn-${ISSUE_NUMBER}" \
  --revision "revisionType=GitHub,gitHubLocation={repository=samhstn/samhstn,commitId=$CODEBUILD_RESOLVED_SOURCE_VERSION}"
