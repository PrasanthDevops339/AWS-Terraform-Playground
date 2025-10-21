import json

print('Loading function')

def lambda_handler(event, context):
    print('lambda function successfully deployed and executed using the module')
    return "success"
    raise Exception('Something went wrong')
