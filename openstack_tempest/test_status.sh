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
# Script to check status of tempest helm chart and collect results.
#
# usage:  ./test_status.sh
# usage:  TIMEOUT=600 ./test_status.sh

# Define Variables
#
# NOTE: User will need to set up the required environment variables
# before executing this script if they differ from the default values.

# SET DEFAULT VALUES
NAMESPACE="${NAMESPACE:-openstack}"
TIMEOUT="${TIMEOUT:-300}"
LOGFILE="${LOGFILE:-/tmp/results.txt}"

# PROCESS COMMAND LINE ARGUMENTS
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --nodelete|--no-delete)
    NODELETE=TRUE
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

### CHECK THAT POD EXISTS ###

PODNAME=`kubectl -n $NAMESPACE get pods -a | grep tempest-run-tests | tail -1 | awk '{print $1 }'`
if [ -z "$PODNAME" ]; then
    echo "FAILED: pod matching [tempest-run-tests] in namespace [$NAMESPACE] does not exist"
    echo "1" && exit 1   
fi

TEMPEST=$(helm list | grep tempest | awk '{print $1}')

### CHECKING THE POD STATUS FREQUENTLY ###

i="0"
while [ $i -lt $TIMEOUT ]; do
    STATUS=`kubectl get pods $PODNAME -n $NAMESPACE | tail -1 | awk '{print $3}'`
    case $STATUS in
        Completed)
            break
            ;;
        Running|PodInitializing|Init:[0-9]*)
            ;;
        *)
            kubectl logs $PODNAME -n $NAMESPACE 2>&1 > $LOGFILE
            echo "PREVIOUS LOGS" >> $LOGFILE
            kubectl logs $PODNAME -n $NAMESPACE --previous 2>&1 >> $LOGFILE
            if [ -z "$NODELETE" ]; then helm delete --purge $TEMPEST >/dev/null; fi
            echo "FAILED: pod [$PODNAME] entered status [$STATUS] - logs saved on host at [$LOGFILE]"
            echo "1" && exit 1
            ;;
    esac
    sleep 10
    i=$[$i+10]
done

### ABORT IF POD DID NOT COMPLETE ###

if ! kubectl get pods $PODNAME -n $NAMESPACE | grep Completed > /dev/null; then
    kubectl logs $PODNAME -n $NAMESPACE 2>&1 > $LOGFILE
    echo "PREVIOUS LOGS" >> $LOGFILE
    kubectl logs $PODNAME -n $NAMESPACE --previous 2>&1 >> $LOGFILE
    if [ -z "$NODELETE" ]; then helm delete --purge $TEMPEST >/dev/null; fi
    echo "FAILED: timeout [$TIMEOUT] exceed by pod [$PODNAME], last status [$STATUS] - logs saved on host at [$LOGFILE]"
    echo "1" && exit 1
fi

### DISPLAY THE TEST RESULTS ###

kubectl logs $PODNAME -n $NAMESPACE > $LOGFILE
TEST_RESULTS=`cat $LOGFILE | sed -n '/Totals/,+7p'`
TEST_RESULTS=`grep -A 7 "^Totals" $LOGFILE`

### DELETE THE HELM DEPLOYMENT ###
if [ -z "$NODELETE" ]; then helm delete --purge $TEMPEST >/dev/null; fi

grep -E -o "Ran: [0-9]+ tests" $LOGFILE && grep -E -o "Passed: [0-9]+" $LOGFILE && grep -E -o "Failed: [0-9]+" $LOGFILE
exit 0

