import json
import time
import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')


def lambda_handler(event, context):
    """
    Trigger CPU spike on a workshop user's EC2 instance using stress-ng.

    Input: {"username": "user123"}
    Output: {
        "success": true,
        "instance_id": "i-xxx",
        "username": "user123",
        "message": "CPU stress started"
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

        # Send SSM command to trigger CPU stress
        # Run stress-ng in background for 300 seconds (5 minutes)
        command = 'nohup stress-ng --cpu 2 --timeout 300s > /dev/null 2>&1 & disown'

        print(f"Sending SSM command to instance {instance_id}: {command}")

        ssm_response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName='AWS-RunShellScript',
            Parameters={'commands': [command]},
            TimeoutSeconds=60
        )

        command_id = ssm_response['Command']['CommandId']

        # Wait for command to complete
        max_attempts = 15
        attempt = 0

        while attempt < max_attempts:
            time.sleep(2)
            attempt += 1

            try:
                result = ssm.get_command_invocation(
                    CommandId=command_id,
                    InstanceId=instance_id
                )

                status = result['Status']
                print(f"Command status: {status}")

                if status in ['Success', 'Failed', 'Cancelled', 'TimedOut']:
                    output = result.get('StandardOutputContent', '')
                    error_output = result.get('StandardErrorContent', '')

                    if status == 'Success':
                        return {
                            'success': True,
                            'instance_id': instance_id,
                            'username': safe_username,
                            'message': 'CPU stress started - running for 300 seconds'
                        }
                    else:
                        return {
                            'success': False,
                            'instance_id': instance_id,
                            'username': safe_username,
                            'error': f'Command {status}: {error_output or output}'
                        }
            except ClientError as e:
                if 'InvocationDoesNotExist' in str(e):
                    continue
                raise

        return {
            'success': False,
            'instance_id': instance_id,
            'username': safe_username,
            'error': 'Command timed out waiting for completion'
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
