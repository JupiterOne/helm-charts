#!/bin/bash

NAMESPACE="j1"

# Add the jupiterone helm chart
echo "helm repo add jupiterone https://jupiterone.github.io/helm-charts"
helm repo add jupiterone https://jupiterone.github.io/helm-charts

# Install/upgrade the jupiterone integration
echo "helm upgrade --install j1-integration ./charts/graph-kubernetes -f values.yaml -n $NAMESPACE --create-namespace"
helm upgrade --install j1-integration ./charts/graph-kubernetes -f values.yaml -n $NAMESPACE --create-namespace

# See the resources created by the helm chart installation
echo "kubectl get all -n $NAMESPACE"
kubectl get all -n $NAMESPACE

# Manually invoke the cron job
# Get the cron job name from the j1 namespace and assign the name to CRONJOB_NAME
echo "kubectl get cronjob -n $NAMESPACE"
CRONJOB_NAME=$(kubectl get cronjob -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')

# Create a job from the cron job
JOB_NAME=${CRONJOB_NAME}-$(date +%s)
echo "kubectl create job --from=cronjob/$CRONJOB_NAME $JOB_NAME -n $NAMESPACE"
kubectl create job --from=cronjob/$CRONJOB_NAME $JOB_NAME -n $NAMESPACE

# Wait for the job to start (timeout after 60 seconds)
echo "Waiting for job to start..."
for i in {1..60}; do
    if kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.active}' | grep -q "1"; then
        echo "Job started successfully"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "Timeout waiting for job to start"
        exit 1
    fi
    sleep 1
done

# Wait for the pod to be running (timeout after 60 seconds)
echo "Waiting for pod to be running..."
POD_NAME=$(kubectl get pods -n $NAMESPACE -l "job-name=$JOB_NAME" -o jsonpath='{.items[0].metadata.name}')
for i in {1..60}; do
    if kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q "Running"; then
        echo "Pod is running"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "Timeout waiting for pod to be running"
        exit 1
    fi
    sleep 1
done

# Check the status of the job
echo "Checking job status..."
echo "kubectl get job $JOB_NAME -n $NAMESPACE"
kubectl get job $JOB_NAME -n $NAMESPACE

# Wait 60 seconds before checking logs
echo "Waiting 60 seconds before checking logs..."
sleep 60

# Check the logs of the job
echo "kubectl logs job/$JOB_NAME -n $NAMESPACE"
kubectl logs job/$JOB_NAME -n $NAMESPACE

# Check the status of the pod
echo "kubectl get pod -n $NAMESPACE"
kubectl get pod -n $NAMESPACE