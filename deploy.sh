#!/bin/bash
#
# Before running, be sure to replace the sample values in the global variables below.
#
# Usage: ./deploy.sh
#
# Created by kylewbanks on 2015-08-14

# Define some global variables
export AUTO_SCALING_GROUP_NAME="EXAMPLE"
export SCALING_POLICY="EXAMPLE"
export ELB_NAME="EXAMPLE"

# Returns the number of instances currently in the AutoScaling group
function getNumInstancesInAutoScalingGroup() {
    local num=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" --query "length(AutoScalingGroups[0].Instances)")    
    local __resultvar=$1
    eval $__resultvar=$num
}

# Returns the number of healthy instances currently in the ELB
function getNumHealthyInstancesInELB() {
    local num=$(aws elb describe-instance-health --load-balancer-name "$ELB_NAME" --query "length(InstanceStates[?State=='InService'])")
    local __resultvar=$1
    eval $__resultvar=$num
}

# Get the current number of desired instances to reset later
export existingNumDesiredInstances=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" --query "AutoScalingGroups[0].DesiredCapacity")

# Determine the number of instances we expect to have online
getNumInstancesInAutoScalingGroup numInstances
numInstancesExpected=$(expr $numInstances \* 2)
echo "Expecting to have $numInstancesExpected instance(s) online."

echo "Will launch $numInstances Instance(s)..."
for i in `seq 1 $numInstances`;
do
    echo "Launching instance..."
    aws autoscaling execute-policy --no-honor-cooldown --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" --policy-name "$SCALING_POLICY"
    sleep 5s
done

# Wait for the number of instances to increase
getNumInstancesInAutoScalingGroup newNumInstances
until [[ "$newNumInstances" == "$numInstancesExpected" ]]; 
do
    echo "Only $newNumInstances instance(s) online in $AUTO_SCALING_GROUP_NAME, waiting for $numInstancesExpected..."
    sleep 10s
    getNumInstancesInAutoScalingGroup newNumInstances
done

# Wait for the ELB to determine the instances are healthy
echo "All instances online, waiting for the Load Balancer to put them In Service..."
getNumHealthyInstancesInELB numHealthyInstances
until [[ "$numHealthyInstances" == "$numInstancesExpected" ]];
do
    echo "Only $numHealthyInstances instance(s) In Service in $ELB_NAME, waiting for $numInstancesExpected..."
    sleep 10s
    getNumHealthyInstancesInELB numHealthyInstances
done

# Update the desired capacity back to it's previous value
echo "Resetting Desired Instances to $existingNumDesiredInstances"
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" --desired-capacity $existingNumDesiredInstances

# Success!
echo "Deployment complete!"
