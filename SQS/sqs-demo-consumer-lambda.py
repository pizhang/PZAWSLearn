import json
import boto3
import logging
import os
from datetime import datetime

#Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ['AWS_REGION']

sqs = boto3.client('sqs', region_name=AWS_REGION)
SQS_QUEUE_URL = os.environ['SQS_QUEUE_URL']

logger.info(f"SQS_QUEUE_URL: {SQS_QUEUE_URL}")
logger.info(f"AWS_REGION: {AWS_REGION}")


def lambda_handler(event, context):
    try:
        # Generate a random message
        messages = sqs.receive_message(
            QueueUrl=SQS_QUEUE_URL,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=5
        ).get('Messages', [])

        processed_count = 0

        for message in messages:
            try:
                # Process the message
                body = json.loads(message['Body'])
                logger.info(f"Processing message: {message['MessageId']}: {body}")

                # business logic here

                # Delete the message from the queue
                sqs.delete_message(
                    QueueUrl=SQS_QUEUE_URL,
                    ReceiptHandle=message['ReceiptHandle']
                )
                processed_count += 1

            except Exception as e:
                logger.error(f"Failed processing {message['MessageId']}: {str(e)}")   

        return {
            'statusCode': 200,
            'body': f"Processed {processed_count} messages"
        }
    except sqs.exceptions.QueueDoesNotExist:
        logger.error(f"Queue does not exist: {str(e)}")
        return {
            'statusCode': 404,
            'body': 'Queue does not exist'
        }

    except Exception as e:
        logger.error(f"Consumer error: {str(e)}")
        return {
            'statusCode': 500,
            'body': 'Failed to process messages'
        }
