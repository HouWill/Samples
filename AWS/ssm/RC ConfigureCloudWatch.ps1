# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel


param ($Name = 'ssm-windows',
        $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Write-Verbose "Windows Run Command Name=$Name, MSIPath=$MSIPath, Region=$Region"
Set-DefaultAWSRegion $Region

$instance = Get-WinEC2Instance $Name -DesiredState 'running'
$instanceId = $instance.InstanceId
Write-Verbose "Name=$Name InstanceId=$instanceId"


$properties = @"
{
    "EngineConfiguration": {
        "PollInterval": "00:00:15",
        "Components": [
            {
                "Id": "PerformanceCounter",
                "FullName": "AWS.EC2.Windows.CloudWatch.PerformanceCounterComponent.PerformanceCounterInputComponent,AWS.EC2.Windows.CloudWatch",
                "Parameters": {
                    "CategoryName": "Memory",
                    "CounterName": "Available MBytes",
                    "InstanceName": "",
                    "MetricName": "Memory",
                    "Unit": "Megabytes",
                    "DimensionName": "InstanceId",
                    "DimensionValue": "$instanceId"
                }
            },
            {
                "Id": "CloudWatchMetrics",
                "FullName": "AWS.EC2.Windows.CloudWatch.CloudWatch.CloudWatchOutputComponent,AWS.EC2.Windows.CloudWatch",
                "Parameters": {
                    "Region": "$Region",
                    "NameSpace": "SSMDemo"
                }
            },
            {
			    "Id": "SSMLogs",
			    "FullName": "AWS.EC2.Windows.CloudWatch.CustomLog.CustomLogInputComponent,AWS.EC2.Windows.CloudWatch",
			    "Parameters": {
				    "LogDirectoryPath": "C:\\Program Files\\Amazon\\Ec2ConfigService\\Logs",
				    "TimestampFormat": "yyyy-MM-dd HH:mm:ss",
				    "Encoding": "UTF-8",
				    "Filter": "Ec2ConfigPluginFramework*",
				    "CultureName": "en-US",
				    "TimeZoneKind": "Local"
			    }
		    },
		    {
			    "Id": "CloudWatchLogs",
			    "FullName": "AWS.EC2.Windows.CloudWatch.CloudWatchLogsOutput,AWS.EC2.Windows.CloudWatch",
			    "Parameters": {
				    "Region": "$Region",
				    "LogGroup": "SSM-Log-Group",
				    "LogStream": "{instance_id}"
			    }
		    }
        ],
        "Flows": {
            "Flows": [
                "PerformanceCounter,CloudWatchMetrics",
			    "SSMLogs,CloudWatchLogs"
            ]
        }
    }
}
"@

#Run Command
Write-Verbose 'Run Command - AWS-InstallApplication'
$startTime = Get-Date
$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -DocumentName 'AWS-ConfigureCloudWatch' `
    -Parameters @{
        status="Enabled"
        properties=$properties
     } 

$obj = @{}
$obj.'CommandId' = $command
$obj.'RunCommandTime' = (Get-Date) - $startTime

Test-SSMOuput $command -ExpectedMinLength 51 -ExpectedMaxLength 51



return $obj