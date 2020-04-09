#!/bin/bash
ENV=dev
PROFILE=''

profileOption=''
bucketName=eds-cf-templates

# Required fields
appName='eds37-timetracking'
rootStackFileName='eds37-timetracking-main.yaml'
# appName='eds-cf-app-example'
# rootStackFileName='main.template.yaml'

if test -z "$appName"; then
    echo "\appName is empty"
    exit 125
fi

if test -z "$rootStackFileName"; then
    echo "\$rootStackFileName is empty"
    exit 125
fi

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -env|-e)
        ENV="$2"
        shift # past argument
        shift # past value
        ;;
    -profile|-p)
        PROFILE="$2"
        shift # past argument
        shift # past value
        ;;
    *)
        echo "Sorry, I don't understand ${key}"
        exit
        ;;
    esac
done

stackName="${ENV}-cf-${appName}"

# Print out parameters
echo "Environmet = ${ENV}"
if [ ! -z ${PROFILE} ]; then
    echo "PROFILE = ${PROFILE}"
    profileOption="--profile ${PROFILE}"
    echo "profile option = ${profileOption}"
fi
echo "StackName = ${stackName}"

if [ $ENV == 'prod' ]; then
    bucketName=eds-cf-templates-prod
fi 

if [ $ENV == 'qa' ]; then
    bucketName=eds-cf-templates-qa
fi 
echo "Bucket name = ${bucketName}"

# Upload files to s3
aws s3 sync . s3://${bucketName}/${ENV}/${appName} \
    --exclude "*" \
    --include "templates/*" \
    --delete \
    $profileOption


# AWS CLI
create_or_update_cf=''
wait_complete=''
if ! aws cloudformation describe-stacks --stack-name $stackName $profileOption; then
    echo "\nStack does not exist, creating ..."
    create_or_update_cf='create-stack'
    wait_complete='stack-create-complete'
else
    echo "\nStack already exist, updating ..."
    create_or_update_cf='update-stack'
    wait_complete='stack-update-complete'
fi

output=$(aws cloudformation \
    ${create_or_update_cf} --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --stack-name ${stackName} \
    --template-url https://s3.amazonaws.com/${bucketName}/${ENV}/${appName}/templates/${rootStackFileName} \
    --parameters file://configs/config-${ENV}.json \
    $profileOption)

status=$?
set -e

echo "$output"

if [ $status -ne 0 ]; then

    # Don't fail for no-op update
    if [[ $output == *"ValidationError"* && $output == *"No updates"* ]]; then
        echo -e "\nFinished create/update - no updates to be performed"
        exit 0
    else
        exit $status
    fi

fi
echo "Waiting for ${create_or_update_cf} the stack"
aws cloudformation wait ${wait_complete} \
    --stack-name ${stackName} \
    $profileOption
