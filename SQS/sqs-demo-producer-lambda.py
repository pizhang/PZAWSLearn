import json
import boto3
import logging
import os
from datetime import datetime
import random
import uuid

#Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ['AWS_REGION']

sqs = boto3.client('sqs', region_name=AWS_REGION)
SQS_QUEUE_URL = os.environ['SQS_QUEUE_URL']

logger.info(f"SQS_QUEUE_URL: {SQS_QUEUE_URL}")
logger.info(f"AWS_REGION: {AWS_REGION}")


def generate_random_message():
    # Generate a random message
    message = {
        'message_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'data': random.randint(1000, 9999)
    }
    return message


def lambda_handler(event, context):
    try:
        # Generate a random message
        message = generate_random_message()
        # Send message to SQS queue
        response = sqs.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(message)
        )   
        logger.info(f"Message sent to SQS queue {SQS_QUEUE_URL}: {message}")
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Message sent to SQS queue'})
        }

    except Exception as e:
        logger.error(f"Error sending message to SQS queue: {str(e)}")   
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal Server Error'})
        }
