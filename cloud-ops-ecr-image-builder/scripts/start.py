#!/usr/bin/python3
import sys
import boto3
import requests
import configparser
import base64
import logging
import xml.etree.ElementTree as ET
import os
import argparse
import re
from bs4 import BeautifulSoup
from os.path import expanduser
from urllib.parse import urlparse, urlunparse

###############################################################################
# Arguments
###############################################################################

# Initialize argument parser
parser = argparse.ArgumentParser()

# Set argument option(s)
parser.add_argument('-e', '--environment', type=str)
parser.add_argument('-g', '--group', type=str)
parser.add_argument('-u', '--username', type=str)
parser.add_argument('-p', '--password', type=str)
parser.add_argument('-r', '--region', type=str, default='us-east-2')

# Parse provided arguments
args = parser.parse_args()

# Check for required arguments
if not args.environment:
    print('Argument -e environment not set')
    sys.exit(0)
elif not args.group:
    print('Argument -g group not set')
    sys.exit(0)
elif not args.username:
    print('Argument -u username not set')
    sys.exit(0)
elif not args.password:
    print('Argument -p password not set')
    sys.exit(0)
elif not args.region:
    print('Argument -r region not set')
    sys.exit(0)

# Set required argument(s)
env = args.environment
group = args.group
username = args.username
password = args.password
region = args.region

###############################################################################
# Variables
###############################################################################

# output format: The AWS CLI output format that will be configured in the
# saml profile (affects subsequent CLI calls)
outputformat = 'json'

# awsconfigfile: The file where this script will store the temp
# credentials under the saml profile
awsconfigfile = '/.aws/credentials'

# SSL certificate verification: Whether or not strict certificate
# verification is done, False should only be used for dev/test
sslverification = True

# idpentryurl: The initial url that starts the authentication process.
idpentryurl = f'https://federate.examplecorp.com/aws-examplecorp-{group}-{env}'

# Uncomment to enable low level debugging
# logging.basicConfig(level=logging.DEBUG)

###############################################################################
# Initiate session handler
###############################################################################
session = requests.Session()

# Programmatically get the SAML assertion
# Opens the initial IdP url and follows all of the HTTP302 redirects, and
# gets the resulting login page
formresponse = session.get(idpentryurl, verify=sslverification)

# Capture the idpauthformsubmiturl, which is the final url after all the 302s
idpauthformsubmiturl = formresponse.url

# Parse the response and extract all the necessary values
# in order to build a dictionary of all of the form values the IdP expects
formsoup = BeautifulSoup(formresponse.text, features="html.parser")
payload = {}

for inputtag in formsoup.find_all(re.compile('(INPUT|input)')):
    name = inputtag.get('name', '')
    value = inputtag.get('value', '')
    if "user" in name.lower():
        payload[name] = username
    elif "email" in name.lower():
        payload[name] = username
    elif "pass" in name.lower():
        payload[name] = password
    else:
        payload[name] = value

# Some IdPs don't explicitly set a form action, but if one is set we should
# build the idpauthformsubmiturl by combining the scheme and hostname
# from the entry url with the form action target
for inputtag in formsoup.find_all(re.compile('(FORM|form)')):
    action = inputtag.get('action')
    if action:
        parsedurl = urlparse(idpentryurl)
        idpauthformsubmiturl = parsedurl.scheme + "://" + parsedurl.netloc + action

# Performs the submission of the IdP login form with the above post data
response = session.post(
    idpauthformsubmiturl,
    data=payload,
    verify=sslverification
)

# Overwrite and delete the credential variables, just for safety
username = '############################################'
password = '############################################'
del username
del password

###############################################################################
# Decode the response and extract the SAML assertion
###############################################################################
soup = BeautifulSoup(response.text, features="html.parser")
assertion = ''

# Look for the SAMLResponse attribute of the input tag
for inputtag in soup.find_all('input'):
    if inputtag.get('name') == 'SAMLResponse':
        assertion = inputtag.get('value')

# Better error handling is required for production use.
if assertion == '':
    print('Response did not contain a valid SAML assertion')
    sys.exit(0)

###############################################################################
# Parse the returned assertion and extract the authorized roles
###############################################################################
awsroles = []
root = ET.fromstring(base64.b64decode(assertion))
for saml2attribute in root.iter('{urn:oasis:names:tc:SAML:2.0:assertion}Attribute'):
    if saml2attribute.get('Name') == 'https://aws.amazon.com/SAML/Attributes/Role':
        for saml2attributevalue in saml2attribute.iter('{urn:oasis:names:tc:SAML:2.0:assertion}AttributeValue'):
            awsroles.append(saml2attributevalue.text)

# Reverse role/principal if needed
for awsrole in awsroles:
    chunks = awsrole.split(',')
    if 'saml-provider' in chunks[0]:
        newawsrole = chunks[1] + ',' + chunks[0]
        index = awsroles.index(awsrole)
        awsroles.insert(index, newawsrole)
        awsroles.remove(awsrole)

###############################################################################
# Ask user which role to assume (if more than one)
###############################################################################
print("")
if len(awsroles) > 1:
    i = 0
    print("Please choose the role you would like to assume:")
    for awsrole in awsroles:
        print('[', i, ']:', awsrole.split(',')[0])
        i += 1
    print("Selection: ", end='')
    selectedroleindex = input()

    if int(selectedroleindex) > (len(awsroles) - 1):
        print('You selected an invalid role index, please try again')
        sys.exit(0)

    role_arn = awsroles[int(selectedroleindex)].split(',')[0]
    principal_arn = awsroles[int(selectedroleindex)].split(',')[1]
else:
    role_arn = awsroles[0].split(',')[0]
    principal_arn = awsroles[0].split(',')[1]

###############################################################################
# Assume role with SAML
###############################################################################
client = boto3.client('sts', region_name=region)
token = client.assume_role_with_saml(
    RoleArn=role_arn,
    PrincipalArn=principal_arn,
    SAMLAssertion=assertion,
    DurationSeconds=7200
)

###############################################################################
# Write credentials to AWS config file
###############################################################################
home = expanduser("~")
filename = home + awsconfigfile

config = configparser.RawConfigParser()
config.read(filename)

profile_name = f'saml-examplecorp-{group}-{env}'
if not config.has_section(profile_name):
    config.add_section(profile_name)

config.set(profile_name, 'output', outputformat)
config.set(profile_name, 'region', region)
config.set(profile_name, 'aws_access_key_id', token["Credentials"]["AccessKeyId"])
config.set(profile_name, 'aws_secret_access_key', token["Credentials"]["SecretAccessKey"])
config.set(profile_name, 'aws_session_token', token["Credentials"]["SessionToken"])

with open(filename, 'w+') as configfile:
    config.write(configfile)

###############################################################################
# Final output
###############################################################################
print('\n--------------------------------------------------------------')
print(f'Your new access key pair has been stored in {filename} under the {profile_name} profile.')
print(f'Your new access key pair will expire at {token["Credentials"]["Expiration"]}')
print('--------------------------------------------------------------\n')

