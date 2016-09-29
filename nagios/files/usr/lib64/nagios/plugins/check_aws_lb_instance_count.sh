#!/bin/bash
#
# Modified by jhiggins 28Sept2015
# Version  : 1.1.0
# Description : Uses AWSCLI to check the number of instances available in ELB. 
# If the number of instance is less than the expected value it will send CRITICAL alert.
# 
# Modifed to take region, ELBName and expected instance count from argv
# and conform to nagios plugin standards

export AWS_ACCESS_KEY_ID="XXXXX"
export AWS_SECRET_ACCESS_KEY="XXXX"

PROGNAME=`/bin/basename $0`
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
REVISION="1.1.0"

. $PROGPATH/utils.sh

print_usage() {
    echo "Usage: $PROGNAME -l ELB_name -r region -n num_instances"
    echo "Usage: $PROGNAME --help"
    echo "Usage: $PROGNAME --version"
}

print_help() {
    print_revision $PROGNAME $REVISION
    echo ""
    print_usage
    echo ""
    echo "check the number of instances available in an AWS ELB"
    echo ""
    support
}

# Make sure the correct number of command line
# arguments have been supplied

if [ $# -lt 1 ]; then
    print_usage
    exit $STATE_UNKNOWN
fi

# Grab the command line arguments

exitstatus=$STATE_WARNING #default

while test -n "$1"; do
    case "$1" in
        --help)
            print_help
            exit $STATE_OK
            ;;
        -h)
            print_help
            exit $STATE_OK
            ;;
        --version)
            print_revision $PROGNAME $REVISION
            exit $STATE_OK
            ;;
        -V)
            print_revision $PROGNAME $REVISION
            exit $STATE_OK
            ;;
        --lb-name)
            ELB_NAME=$2
            shift
            ;;
        -l)
            ELB_NAME=$2
            shift
            ;;
        --region)
            REGION=$2
            shift
            ;;
        -r)
            REGION=$2
            shift
            ;;
        --num-instances)
            INSTANCE_COUNT=$2
            shift
            ;;
        -n)
            INSTANCE_COUNT=$2
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            print_usage
            exit $STATE_UNKNOWN
            ;;
    esac
    shift
done




#echo $REGION
#echo $ELB_NAME
#echo $INSTANCE_COUNT


ELB_INSTANCE_COUNT=`aws --region ${REGION} elb describe-instance-health --load-balancer-name ${ELB_NAME} --output text | wc -l`
#ELB_INSTANCE_COUNT=`aws --region ${REGION} elb describe-instance-health --load-balancer-name ${ELB_NAME} --output text | grep InService | wc -l`


if [ "${ELB_INSTANCE_COUNT}" -eq "${INSTANCE_COUNT}" ]; then
	echo "OK: Expected ${INSTANCE_COUNT} and found ${ELB_INSTANCE_COUNT} in ELB ${ELB_NAME}"
	exitstatus=${STATE_OK}
elif [ "${ELB_INSTANCE_COUNT}" -lt "${INSTANCE_COUNT}" ]; then
	echo "CRIT: Expected ${INSTANCE_COUNT} but found ${ELB_INSTANCE_COUNT} in ELB ${ELB_NAME}"
	exitstatus=${STATE_CRITICAL}
else [ "${ELB_INSTANCE_COUNT}" -gt "${INSTANCE_COUNT}" ]
	echo "WARN: Expected ${INSTANCE_COUNT} but found ${ELB_INSTANCE_COUNT} in ELB ${ELB_NAME}"
	exitstatus=${STATE_WARNING}
fi

exit ${exitstatus}
