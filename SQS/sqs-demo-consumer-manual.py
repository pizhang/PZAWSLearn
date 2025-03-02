import boto3

sqs = boto3.client('sqs', region_name='ap-southeast-2')

queue_url = <Your SQS Queue URL>
response = sqs.receive_message(QueueUrl=queue_url)

print(response)
