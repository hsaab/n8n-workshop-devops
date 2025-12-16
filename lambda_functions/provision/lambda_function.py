import json
import os
import time
import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client('ec2')
cloudwatch = boto3.client('cloudwatch')

# Environment variables from Terraform
AMI_ID = os.environ.get('AMI_ID')
SUBNET_ID = os.environ.get('SUBNET_ID')
SECURITY_GROUP_ID = os.environ.get('SECURITY_GROUP_ID')
INSTANCE_PROFILE_ARN = os.environ.get('INSTANCE_PROFILE_ARN')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
DISK_THRESHOLD = int(os.environ.get('DISK_THRESHOLD', '80'))

# CloudWatch Agent user data script
USER_DATA = '''#!/bin/bash
yum install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'EOF'
{
  "metrics": {
    "namespace": "Workshop",
    "metrics_collected": {
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
'''


def lambda_handler(event, context):
    """
    Provision an EC2 instance for a workshop user.

    Input: {"username": "user123"}
    Output: {
        "success": true,
        "instance_id": "i-xxx",
        "instance_name": "workshop-user123",
        "public_ip": "x.x.x.x",
        "username": "user123",
        "exists": false
    }
    """
    try:
        # Parse input
        if isinstance(event, str):
            event = json.loads(event)

        username = event.get('username')
        if not username:
            return {
                'success': False,
                'error': 'Missing required field: username'
            }

        # Sanitize username for use in resource names
        safe_username = ''.join(c for c in username if c.isalnum() or c in '-_').lower()
        instance_name = f"workshop-{safe_username}"
        alarm_name = f"workshop-{safe_username}-disk-high"

        # Check if instance already exists for this user
        existing = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:workshop-user', 'Values': [safe_username]},
                {'Name': 'instance-state-name', 'Values': ['pending', 'running', 'stopping', 'stopped']}
            ]
        )

        for reservation in existing['Reservations']:
            for instance in reservation['Instances']:
                if instance['State']['Name'] in ['pending', 'running', 'stopping', 'stopped']:
                    # Instance already exists
                    public_ip = instance.get('PublicIpAddress', 'pending')
                    return {
                        'success': True,
                        'instance_id': instance['InstanceId'],
                        'instance_name': instance_name,
                        'public_ip': public_ip,
                        'username': safe_username,
                        'exists': True,
                        'message': 'Instance already exists for this user'
                    }

        # Create new EC2 instance
        response = ec2.run_instances(
            ImageId=AMI_ID,
            InstanceType='t3.micro',
            MinCount=1,
            MaxCount=1,
            SubnetId=SUBNET_ID,
            SecurityGroupIds=[SECURITY_GROUP_ID],
            IamInstanceProfile={'Arn': INSTANCE_PROFILE_ARN},
            UserData=USER_DATA,
            BlockDeviceMappings=[
                {
                    'DeviceName': '/dev/xvda',
                    'Ebs': {
                        'VolumeSize': 8,
                        'VolumeType': 'gp3',
                        'DeleteOnTermination': True
                    }
                }
            ],
            TagSpecifications=[
                {
                    'ResourceType': 'instance',
                    'Tags': [
                        {'Key': 'Name', 'Value': instance_name},
                        {'Key': 'workshop-user', 'Value': safe_username},
                        {'Key': 'workshop', 'Value': 'devops-workshop'}
                    ]
                },
                {
                    'ResourceType': 'volume',
                    'Tags': [
                        {'Key': 'Name', 'Value': f"{instance_name}-volume"},
                        {'Key': 'workshop-user', 'Value': safe_username},
                        {'Key': 'workshop', 'Value': 'devops-workshop'}
                    ]
                }
            ]
        )

        instance_id = response['Instances'][0]['InstanceId']

        # Wait for instance to be running
        print(f"Waiting for instance {instance_id} to be running...")
        waiter = ec2.get_waiter('instance_running')
        waiter.wait(
            InstanceIds=[instance_id],
            WaiterConfig={'Delay': 5, 'MaxAttempts': 40}
        )

        # Get instance details including public IP
        instance_info = ec2.describe_instances(InstanceIds=[instance_id])
        instance = instance_info['Reservations'][0]['Instances'][0]
        public_ip = instance.get('PublicIpAddress', 'No public IP assigned')

        # Create CloudWatch alarm for disk usage
        cloudwatch.put_metric_alarm(
            AlarmName=alarm_name,
            AlarmDescription=f'Disk usage alert for workshop user {safe_username}',
            ActionsEnabled=True,
            AlarmActions=[SNS_TOPIC_ARN],
            MetricName='disk_used_percent',
            Namespace='Workshop',
            Statistic='Average',
            Dimensions=[
                {
                    'Name': 'InstanceId',
                    'Value': instance_id
                },
                {
                    'Name': 'path',
                    'Value': '/'
                },
                {
                    'Name': 'device',
                    'Value': 'xvda1'
                },
                {
                    'Name': 'fstype',
                    'Value': 'xfs'
                }
            ],
            Period=60,
            EvaluationPeriods=1,
            Threshold=DISK_THRESHOLD,
            ComparisonOperator='GreaterThanThreshold',
            TreatMissingData='notBreaching'
        )

        return {
            'success': True,
            'instance_id': instance_id,
            'instance_name': instance_name,
            'public_ip': public_ip,
            'username': safe_username,
            'exists': False,
            'alarm_name': alarm_name,
            'message': 'Instance provisioned successfully'
        }

    except ClientError as e:
        print(f"AWS Error: {e}")
        return {
            'success': False,
            'error': str(e)
        }
    except Exception as e:
        print(f"Error: {e}")
        return {
            'success': False,
            'error': str(e)
        }
