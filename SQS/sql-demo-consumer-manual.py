import boto3

sqs = boto3.client('sqs', region_name='ap-southeast-2')

queue_url = "https://sqs.ap-southeast-2.amazonaws.com/509399591785/basic-demo"
response = sqs.receive_message(QueueUrl=queue_url)

print(response)
