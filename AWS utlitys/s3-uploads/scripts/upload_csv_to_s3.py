#!/usr/bin/env python3

import argparse
import boto3
from botocore.exceptions import ClientError


def upload_file(bucket_name, object_key, file_path, region):
    s3 = boto3.client("s3", region_name=region)

    try:
        s3.upload_file(
            Filename=file_path,
            Bucket=bucket_name,
            Key=object_key,
            ExtraArgs={
                "ContentType": "text/csv"
            }
        )

        print(
            f"Uploaded {file_path} "
            f"to s3://{bucket_name}/{object_key}"
        )

    except ClientError as error:
        print(f"Upload failed: {error}")
        raise


def main():
    parser = argparse.ArgumentParser(
        description="Upload CSV file to S3"
    )

    parser.add_argument("--bucket", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--file", required=True)
    parser.add_argument("--region", required=True)

    args = parser.parse_args()

    upload_file(
        bucket_name=args.bucket,
        object_key=args.key,
        file_path=args.file,
        region=args.region
    )


if __name__ == "__main__":
    main()
