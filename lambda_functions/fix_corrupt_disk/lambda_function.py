import json
import time
import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')


def lambda_handler(event, context):
    """
    Fix a corrupt disk by removing the immutable flag and deleting all filler files.
    This is the "human intervention" that fixes what the automated reset_disk couldn't.

    Input: {"username": "user123"}
    Output: {
        "success": true,
        "instance_id": "i-xxx",
        "username": "user123",
        "disk_status": "... df -h output ...",
        "message": "Corrupt disk fixed. Immutable flag removed and files deleted."
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

        # Send SSM command to remove immutable flag and delete all filler files
        # First remove the immutable flag (suppress error if file doesn't exist), then delete all filler files
        # Note: Use /var/tmp instead of /tmp because /tmp is often tmpfs (RAM-based)
        command = 'chattr -i /var/tmp/filler_corrupt.dat 2>/dev/null || true && rm -f /var/tmp/filler*.dat && df -h /'

        print(f"Sending SSM command to instance {instance_id}: {command}")

        ssm_response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName='AWS-RunShellScript',
            Parameters={'commands': [command]},
            TimeoutSeconds=60
        )

        command_id = ssm_response['Command']['CommandId']

        # Wait for command to complete
        max_attempts = 30
        attempt = 0
        output = None

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
                            'disk_status': output,
                            'message': 'Corrupt disk fixed. Immutable flag removed and files deleted.'
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
