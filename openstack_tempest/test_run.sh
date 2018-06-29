#!/bin/bash
#
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Script to run the tempest helm chart and collect results.
# Only one copy of tempest is allowed to run at a time.
#
# usage:  ./test_run.sh
# usage:  OS_USERNAME=tempest ./test_run.sh

# Define Variables
#
# NOTE: User will need to set up the required environment variables
# before executing this script if they differ from the default values.

# SET DEFAULT VALUES
export OS_USERNAME=${OS_USERNAME:-admin}
export OS_PASSWORD=${OS_PASSWORD:-password}
export OS_REGION_NAME=${OS_REGION_NAME:-RegionOne}
export NAMESPACE="${NAMESPACE:-openstack}"

TIMEOUT="${TIMEOUT:-900}"

### CHECK THAT HEAT IS RUNNING ###
ERROR=$(kubectl get pods -n $NAMESPACE)
if [ "$?" -ne 0 ] || [ "$(kubectl get pods -n $NAMESPACE | grep '^heat' | grep Running | wc -l)" -lt 3 ] ; then
    echo "FAILED:  It does not appear that openstack heat is running."
    kubectl get pods -n $NAMESPACE | grep "^heat"
    exit 1
fi

### CHECK THAT OPENSTACK SETTINGS ARE CORRECT (also forces download of docker image if needed) ###
ERROR=$(./run_openstack_cli.sh stack list)
if [ "$?" -ne 0 ]; then
    ERROR="${ERROR:- }"
    echo "FAILED:  Cannot access openstack.  Please verify settings."
    echo "ERROR:   ${ERROR: : -1}"
    echo "OS_REGION_NAME = ${OS_REGION_NAME}"
    echo "OS_USERNAME    = ${OS_USERNAME}"
    echo "OS_PASSWORD    = ${OS_PASSWORD}"
    exit 1
fi

### Delete any partially deleted instances ###
for CHART in `helm ls --all | grep tempest | grep -v DEPLOYED | awk '{print $1}'`; do helm delete $CHART --purge; done

## Check that tempest is not already running
TEMPEST=$(helm list | grep tempest | awk '{print $1}')
if [ -n "$TEMPEST" ]; then
    ## CHECK POD STATUS
    PODNAME=`kubectl -n $NAMESPACE get pods -a | grep tempest-run-tests | tail -1 | awk '{print $1 }'`
    STATUS=`kubectl get pods $PODNAME -n $NAMESPACE | tail -1 | awk '{print $3}'`
    if [ "$STATUS" != "Completed" ]; then
        echo "FAILED:  Tempest helm deploy [$TEMPEST] already running."
        echo "Please allow the current tempest run to complete or manually clean up if the run failed."
        exit 1
    else
        echo "WARNING:  deleting completed previous tempest deploy [$TEMPEST] pod [$PODNAME]"
        helm delete --purge $TEMPEST
        sleep 10
    fi
fi

## Clone Helm-Chart from Akraino Gerrit
## TO UPDATE TO THE LATEST TEMPEST HELM CHART:
##   git clone openstack-helm and openstack-helm-infra
##   mkdir -p openstack-helm/tempest/charts
##   cp -R ./openstack-helm-infra/helm-toolkit ./openstack-helm/tempest/charts

#cd /opt
#git clone http://gerrit.att-akraino.org/test_automation.git

### Make private file for settings ###
(umask 066; touch ./overrides.yaml)
cat >./overrides.yaml <<EOF
endpoints:
  identity:
    auth:
      admin:
        region_name: $OS_REGION_NAME
        username: $OS_USERNAME
        password: $OS_PASSWORD
        project_name: admin
        user_domain_name: default
        project_domain_name: default
      tempest:
        role: admin
        region_name: $OS_REGION_NAME
        username: tempest
        password: $OS_PASSWORD
        project_name: service
        user_domain_name: default
        project_domain_name: default
EOF

### Install the tempest using helm charts ###
helm install ./tempest -f ./tempest/values.yaml -f ./overrides.yaml --namespace $NAMESPACE --name test-tempest --wait 2>&1  || exit 1

### Helm chart is deploying... ###
TEMPEST=$(helm list | grep tempest | awk '{print $1}')
echo "Created tempest helm deployment [$TEMPEST]"
exit 0

