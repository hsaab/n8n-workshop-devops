import json
import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client('ec2')
cloudwatch = boto3.client('cloudwatch')


def lambda_handler(event, context):
    """
    Teardown EC2 instance and CloudWatch alarm for a workshop user.

    Input: {"username": "user123"}
    Output: {
        "success": true,
        "terminated_instances": ["i-xxx"],
        "deleted_alarms": ["workshop-user123-disk-high"],
        "username": "user123"
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

        # Sanitize username
        safe_username = ''.join(c for c in username if c.isalnum() or c in '-_').lower()

        # Both disk and CPU alarms to delete
        alarm_names = [
            f"workshop-{safe_username}-disk-high",
            f"workshop-{safe_username}-cpu-high"
        ]

        terminated_instances = []
        deleted_alarms = []

        # Find instances with the workshop-user tag
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:workshop-user', 'Values': [safe_username]},
                {'Name': 'instance-state-name', 'Values': ['pending', 'running', 'stopping', 'stopped']}
            ]
        )

        instance_ids = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])

        # Terminate instances
        if instance_ids:
            print(f"Terminating instances: {instance_ids}")
            ec2.terminate_instances(InstanceIds=instance_ids)
            terminated_instances = instance_ids

        # Delete CloudWatch alarms (both disk and CPU)
        try:
            alarms = cloudwatch.describe_alarms(AlarmNames=alarm_names)
            existing_alarms = [a['AlarmName'] for a in alarms['MetricAlarms']]
            if existing_alarms:
                cloudwatch.delete_alarms(AlarmNames=existing_alarms)
                deleted_alarms = existing_alarms
                print(f"Deleted alarms: {existing_alarms}")
        except ClientError as e:
            print(f"Error deleting alarms: {e}")

        return {
            'success': True,
            'terminated_instances': terminated_instances,
            'deleted_alarms': deleted_alarms,
            'username': safe_username,
            'message': f"Teardown complete. Terminated {len(terminated_instances)} instance(s)."
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
