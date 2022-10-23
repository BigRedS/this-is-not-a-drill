import logging
import os
from boto3 import resource 
import random
import json

logger = logging.getLogger()

def lambda_handler(event, context):
    logger.setLevel('INFO')
    logger.debug('Event: %s', event)

    global s3_resource
    s3_resource = resource('s3')
    location = "eu-west-2"
    bucket_name = 'notdrills'
    bucket = s3_resource.Bucket(bucket_name)
    keys = []
    for o in bucket.objects.all():
        keys.append(o.key)
        
    
    key = random.choice(keys)
    name = key.split(.)[0]   
    
    ret = {
        "url": "https://" + bucket_name +".s3." + location + ".amazonaws.com/" + key
        "name": name
    }
    
    return {
        'statusCode': 200,
        'headers' : {
            'Access-Control-Allow-Origin': '*',
        },
        'body': json.dumps(ret)
    }

