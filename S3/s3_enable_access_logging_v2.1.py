"""
This script enables server access logging for all S3 buckets in an AWS account.
It checks if server access logging is already enabled for each bucket.
If not, it enables server access logging for that bucket.
The script skips buckets for CloudFormation templates and the destination logging bucket.
"""

import boto3

# Initialize S3 client
s3 = boto3.client('s3')
ssm = boto3.client('ssm')

# SSM parameter name for the destination bucket
SSM_PARAMETER_NAME = '/secure/s3/logging/destination-bucket'

def get_destination_bucket_name():
    """Get the destination bucket name from SSM parameter store"""
    try:
        response = ssm.get_parameter(Name=SSM_PARAMETER_NAME, WithDecryption=True)
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Error getting destination bucket name from SSM: {e}")
        raise


def enable_access_logging(bucket_name, destination_bucket_name):
    """Enable server access logging for one bucket"""
    try:
        # Check if server access logging is already enabled
        response = s3.get_bucket_logging(Bucket=bucket_name)
        if 'LoggingEnabled' in response:
            target_bucket = response['LoggingEnabled']['TargetBucket']
            target_prefix = response['LoggingEnabled']['TargetPrefix']
            if target_bucket == destination_bucket_name and target_prefix == f'{bucket_name}/':
                print('Server access logging is already correctly enabled '
                      f'for bucket: {bucket_name}')
                return
            
            print(f'Server access logging is already enabled for bucket: {bucket_name}, '
                  'but not for the correct destination bucket or prefix.')
            return
     
        # If server access logging is not enabled, enable it
        logging_config = {
            'LoggingEnabled': {
                'TargetBucket': destination_bucket_name,
                'TargetPrefix': f'{bucket_name}/'
            }
        }
        s3.put_bucket_logging(Bucket=bucket_name, BucketLoggingStatus=logging_config)
        print(f"Enabled server access logging for bucket: {bucket_name}")
    except Exception as e:
        print(f"Error enabling server access logging for bucket {bucket_name}: {e}")


def main():
    """Main function to list all S3 buckets and enable server access logging if not enabled yet"""
    try:
        # Get the destination bucket name from SSM parameter store
        destination_bucket_name = get_destination_bucket_name()
        print(f"Destination bucket name: {destination_bucket_name}")

        # List all S3 buckets
        response = s3.list_buckets()
        buckets = response['Buckets']

        # Loop through each bucket and enable server access logging if not enabled
        for bucket in buckets:
            bucket_name = bucket['Name']

            # Skip the destination logging bucket
            if bucket_name == destination_bucket_name:
                print(f"Skipping destination logging bucket: {bucket_name}")
                continue

            # Skip buckets for CloudFormation templates
            if bucket_name.startswith('cf-templates-'):
                print(f"Skipping CloudFormation templates bucket: {bucket_name}")
                continue

            enable_access_logging(bucket_name, destination_bucket_name)
            print(f"Bucket: {bucket_name}")

    except Exception as e:
        print(f"Error listing S3 buckets: {e}")


if __name__ == "__main__":
    main()
