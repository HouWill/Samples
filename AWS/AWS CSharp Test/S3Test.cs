using System;
using System.Collections.Generic;
using Amazon.S3;
using Amazon.S3.Model;
using Amazon.SecurityToken;
using Amazon.SecurityToken.Model;
using Amazon.Runtime;

namespace AWS_CSharp_Test
{
    class S3Test
    {
        public void CreateS3Bucket(string bucketName, string key, Credentials credentials, AmazonS3Config config)
        {
            var s3Client = new AmazonS3Client(credentials.AccessKeyId, credentials.SecretAccessKey, credentials.SessionToken, config);

            string content = "Hello World2!";

            // Put an object in the user's "folder".
            s3Client.PutObject(new PutObjectRequest
            {
                BucketName = bucketName,
                Key = key,
                ContentBody = content
            });

            Console.WriteLine("Updated key={0} with content={1}", key, content);
        }
    }
}
