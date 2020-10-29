#!/bin/bash

ENV_FILE='.env'

touch $ENV_FILE
source $ENV_FILE

if [[ -z "$GITHUB_MASTER_BRANCH" ]]; then
  echo "GITHUB_MASTER_BRANCH=master" >> $ENV_FILE
fi

if [[ -z "$SAMHSTN_PA_TOKEN" ]]; then
  echo "Required environment variable SAMHSTN_PA_TOKEN is not defined"
  exit 1
fi

if [[ -z "$SAMHSTN_NOTIFICATION_EMAIL" ]]; then
  echo "Required environment variable SAMHSTN_NOTIFICATION_EMAIL is not defined"
  exit 1
fi

if [[ -z "$AWS_ADMIN_ACCOUNT_ID" ]]; then
  AWS_ADMIN_ACCOUNT_ID=$(aws sts get-caller-identity --profile samhstn-admin --query Account --output text)
  echo "AWS_ADMIN_ACCOUNT_ID=$AWS_ADMIN_ACCOUNT_ID" >> $ENV_FILE
fi

if [[ -z "$AWS_ROOT_ACCOUNT_ID" ]]; then
  AWS_ROOT_ACCOUNT_ID=$(aws sts get-caller-identity --profile samhstn-root --query Account --output text)
  echo "AWS_ROOT_ACCOUNT_ID=$AWS_ROOT_ACCOUNT_ID" >> $ENV_FILE
fi

if [[ -z $TEMP_PASSWORD ]]; then
  TEMP_PASSWORD=$(node -e "console.log(Math.random().toString(36).slice(2))")
  echo "TEMP_PASSWORD=$TEMP_PASSWORD" >> $ENV_FILE
fi

if [[ -z $CERTIFICATE ]]; then
  CERTIFICATE=$(aws acm list-certificates --query "CertificateSummaryList[?DomainName=='samhstn.com'].CertificateArn|[0]" --output text)
  echo "CERTIFICATE=$CERTIFICATE" >> $ENV_FILE
fi

if ! [ -d infra/venv ]; then
  echo "creating new venv"
  python3 -m venv infra/venv
  infra/venv/bin/python3 -m pip install --upgrade pip
  infra/venv/bin/pip install -r infra/requirements.txt
fi

aws cloudformation deploy \
  --profile samhstn-root \
  --stack-name samhstn \
  --template-file ./infra/root/iam.yml \
  --no-fail-on-empty-changeset \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    Project=Samhstn \
    AccountId=$AWS_ADMIN_ACCOUNT_ID | tr '\n' ' ' | sed 's/^ //' | sed 's/  / /g'

aws cloudformation deploy \
  --profile samhstn-root \
  --stack-name samhstn-setup \
  --template-file ./infra/root/setup.yml \
  --no-fail-on-empty-changeset \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    EmailBucket=samhstn-mail-$AWS_ROOT_ACCOUNT_ID \
    CloudformationBucket=samhstn-cfn-$AWS_ROOT_ACCOUNT_ID | tr '\n' ' ' | sed 's/^ //' | sed 's/  / /g'

mkdir -p infra/cfn_output/root

echo 'Packaging root main.yml'
PACKAGE_ERR="$(aws cloudformation package \
  --profile samhstn-root \
  --template ./infra/root/main.yml \
  --s3-bucket samhstn-cfn-$AWS_ROOT_ACCOUNT_ID \
  --output-template-file infra/cfn_output/root/main.yml 2>&1)"

if ! [[ $PACKAGE_ERR =~ "Successfully packaged artifacts" ]]; then
  echo "ERROR while running 'aws cloudformation package' command:"
  echo $PACKAGE_ERR
  exit 1
fi

aws cloudformation deploy \
  --profile samhstn-root \
  --stack-name samhstn-main \
  --template-file ./infra/cfn_output/root/main.yml \
  --no-fail-on-empty-changeset \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    FromEmail=hello@samhstn.com \
    NotificationEmail=$SAMHSTN_NOTIFICATION_EMAIL | tr '\n' ' ' | sed 's/^ //' | sed 's/  / /g'

if [[ -z $(aws ses --profile samhstn-root describe-active-receipt-rule-set) ]]; then
  echo "setting rule set"
  aws ses --profile samhstn-root set-active-receipt-rule-set --rule-set-name SamhstnRuleSet
fi

aws cloudformation deploy \
  --profile samhstn-admin \
  --stack-name project-iam \
  --template-file ./infra/samhstn/project-iam.yml \
  --no-fail-on-empty-changeset \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    TempPassword=$TEMP_PASSWORD \
    RootAccountId=$AWS_ROOT_ACCOUNT_ID | tr '\n' ' ' | sed 's/^ //' | sed 's/  / /g'

aws cloudformation deploy \
  --profile samhstn-admin \
  --stack-name setup \
  --template-file ./infra/samhstn/setup.yml \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    CloudformationBucket=samhstn-cfn-$AWS_ADMIN_ACCOUNT_ID \
    CodeBuildBucket=samhstn-codebuild-$AWS_ADMIN_ACCOUNT_ID \
    CodePipelineBucket=samhstn-codepipeline-$AWS_ADMIN_ACCOUNT_ID \
    Certificate=$CERTIFICATE | tr '\n' ' ' | sed 's/^ //' | sed 's/  / /g'

mkdir -p infra/cfn_output/samhstn

PACKAGE_ERR="$(aws cloudformation package \
  --profile samhstn-admin \
  --template ./infra/samhstn/main.yml \
  --s3-bucket samhstn-cfn-$AWS_ADMIN_ACCOUNT_ID \
  --output-template-file infra/cfn_output/samhstn/main.yml 2>&1)"

if ! [[ $PACKAGE_ERR =~ "Successfully packaged artifacts" ]]; then
  echo "ERROR while running 'aws cloudformation package' command:"
  echo $PACKAGE_ERR
  exit 1
fi

ROUTE_53_ROLE_ARN="$(aws cloudformation describe-stacks \
  --profile samhstn-root \
  --stack-name samhstn-route53 \
  --query "Stacks[*].Outputs[?OutputKey=='Route53RoleArn'].OutputValue|[0][0]" \
  --output text 2>&1)"

if [[ $ROUTE_53_ROLE_ARN =~ "arn:aws:iam::$AWS_ROOT_ACCOUNT_ID:role/samhstn-route53" ]];then
  aws cloudformation deploy \
    --profile samhstn-admin \
    --stack-name main \
    --template-file ./infra/cfn_output/samhstn/main.yml \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      GithubPAToken=$SAMHSTN_PA_TOKEN \
      GithubMasterBranch=$GITHUB_MASTER_BRANCH \
      Route53RoleArn=$ROUTE_53_ROLE_ARN | tr '\n' ' ' | sed 's/^ //' | sed 's/  / /g'
else
  aws cloudformation deploy \
    --profile samhstn-admin \
    --stack-name main \
    --template-file ./infra/cfn_output/samhstn/main.yml \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      GithubPAToken=$SAMHSTN_PA_TOKEN \
      GithubMasterBranch=$GITHUB_MASTER_BRANCH | tr '\n' ' ' | sed 's/^ //' | sed 's/  / /g'

  DEPLOYMENT_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name main \
    --query "Stacks[*].Outputs[?OutputKey=='DeploymentRoleArn'].OutputValue|[0][0]" \
    --output text)

  aws cloudformation deploy \
    --profile samhstn-root \
    --stack-name samhstn-route53 \
    --template-file ./infra/root/samhstn-route53.yml \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides \
      DeploymentRoleArn=$DEPLOYMENT_ROLE_ARN | tr '\n' ' ' | sed 's/^ //' | sed 's/  / /g'

  aws cloudformation deploy \
    --profile samhstn-admin \
    --stack-name main \
    --template-file ./infra/cfn_output/samhstn/main.yml \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      GithubPAToken=$SAMHSTN_PA_TOKEN \
      GithubMasterBranch=$GITHUB_MASTER_BRANCH \
      Route53RoleArn=$ROUTE_53_ROLE_ARN | tr '\n' ' ' | sed 's/^ //' | sed 's/  / /g'
fi

./infra/venv/bin/python ./infra/configure_github_webhook.py
