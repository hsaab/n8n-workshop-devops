import json
import time
import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')


def lambda_handler(event, context):
    """
    Kill runaway processes and restart a workshop user's EC2 instance.

    Input: {"username": "user123"}
    Output: {
        "success": true,
        "instance_id": "i-xxx",
        "username": "user123",
        "actions": ["killed stress-ng", "rebooted instance"],
        "message": "Process killed and instance rebooted"
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

        # Find running instance for this user
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:workshop-user', 'Values': [safe_username]},
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )

        instance_id = None
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                break
            if instance_id:
                break

        if not instance_id:
            return {
                'success': False,
                'error': f'No running instance found for user: {safe_username}'
            }

        actions = []

        # Step 1: Kill stress-ng process using SSM
        kill_command = 'pkill -9 stress-ng || true'

        print(f"Sending SSM command to instance {instance_id}: {kill_command}")

        ssm_response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName='AWS-RunShellScript',
            Parameters={'commands': [kill_command]},
            TimeoutSeconds=30
        )

        command_id = ssm_response['Command']['CommandId']

        # Wait for kill command to complete
        max_attempts = 15
        attempt = 0
        kill_success = False

        while attempt < max_attempts:
            time.sleep(2)
            attempt += 1

            try:
                result = ssm.get_command_invocation(
                    CommandId=command_id,
                    InstanceId=instance_id
                )

                status = result['Status']
                print(f"Kill command status: {status}")

                if status in ['Success', 'Failed', 'Cancelled', 'TimedOut']:
                    if status == 'Success':
                        actions.append('killed stress-ng')
                        kill_success = True
                    else:
                        error_output = result.get('StandardErrorContent', '')
                        print(f"Kill command failed: {error_output}")
                    break
            except ClientError as e:
                if 'InvocationDoesNotExist' in str(e):
                    continue
                raise

        # Step 2: Reboot the instance using EC2 API
        print(f"Rebooting instance {instance_id}")
        ec2.reboot_instances(InstanceIds=[instance_id])
        actions.append('rebooted instance')

        return {
            'success': True,
            'instance_id': instance_id,
            'username': safe_username,
            'actions': actions,
            'message': 'Process killed and instance rebooted'
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
