Runbook with Mast

All the pertinent information can be found in following files  
#### clari:  
`gateways/gw1_spec.json`  
`gateways/gw2_spec.json`  
`gateways/gw3_spec.json`  
`gateways/gw4_spec.json`  
#### wingman:  
`wingman/gateways/gw1_spec.json`  
`wingman/gateways/gw2_spec.json`  
`wingman/gateways/gw3_spec.json` 

of this directory.  


Search in those files for `cluster` for the name of the ECS cluster where the service is deployed.  
Search `name` and look for the name under `ecs->service->name`. This is the name of the ECS service.  
You can use these values to search for the service in the ECS console. This is helpful for troubleshooting.  
Other information like security group IDs, subnets, environment variables, and secrets can all be found in the spec as well.

We recommend using the mast container.
1. Build the mast container
    * `cd ~/Documents`
    * `git clone git@github.com:clari/mast.git`
    * `cd mast`
    * `DOCKER=podman make local-quick` // with the latest from the mast if you have `podman` instead of `docker`
### or
2. You can also pull the image from ECR (amd64 only)
    * `aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 374926383693.dkr.ecr.us-east-1.amazonaws.com`
    * `docker pull 374926383693.dkr.ecr.us-east-1.amazonaws.com/mast:latest` 
    
.. 
### Prerequisites
1. Set the default AWS profile to whichever environment you are targeting. I make a copy of the ~/.aws directory and changed the `default` credential in the copy when working with different AWS accounts. This directory is mounted to the docker container since Mast needs AWS crendentials. e.g. `cp -r ~/.aws ~/tempaws`

3. Set local environment variables
    * `export LOCAL_AWS_CREDS=~/tempaws/`
        *  This is where the local AWS creds are 

    * `export SPEC_URL=https://raw.githubusercontent.com/yahooo`
        *  This is the URL path to the raw service spec document in Github. This is not used in the seceng deployments but a placeholder is needed.

    * `export PATH_TO_SPEC_JSON=gateways/gw1_spec.json`
        *  This is the local file of the same service spec document. **Absolute path is preferred**. (You could curl Github if you wanted but whatever. You're probably running these commands on your local machine) 
    * The only additonal step is exporting the TASK_DEFINITION_ARN which will be output from the `create_ecs_task_definition` step. You may write automation around this if you want

### First step sanity check
`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast perl /usr/local/bin/validate_cloud_spec --environment prestaging --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})"`

If this step does not run successfully, nothing else will.
```
{
    "global_state": {},
    "cloud_spec_json": "{\"version\":\"2.0\",\"deploy\":{\"provider\":\"harness\",\"harnessConfiguration\":{\"trigger\":{\"method\":\"POST\",\"url\":{\"prestaging\":null,\"staging\":null},\"headers\":[\"content-type: application/json\"],\"body\":\"{\\\"application\\\":\\\"dkglk;d;flgk;lsdfkg;lk\\\",\\\"artifacts\\\":[{\\\"service\\\":\\\"graphql\\\",\\\"buildNumber\\\":\\\"123\\\"},{\\\"service\\\":\\\"example\\\",\\\"buildNumber\\\":\\\"123\\\"}]}\"}}},\"aws\":{\"region\":\"us-east-1\",\"elb\":{\"loadBalancers\":[{\"type\":\"application\",\"name\":{\"prestaging\":\"example-lb-int-prestaging\",\"staging\":\"example-lb-int-staging\"},\"securityGroups\":{\"prestaging\":\"sg-0f8cca4c407546a36\",\"staging\":\"sg-09a8341095bfd82c8\"},\"listeners\":[{\"protocol\":\"HTTPS\",\"port\":443,\"rules\":[{\"placement\":\"end\",\"conditions\":{\"prestaging\":[{\"Field\":\"host-header\",\"Values\":[\"hello.example.prestaging.clari.io\"]}],\"staging\":[{\"Field\":\"host-header\",\"Values\":[\"goodbye.example.staging.clari.io\"]}]},\"action\":{\"type\":\"forward\",\"targetGroupName\":{\"prestaging\":\"example-prestaging-111\",\"staging\":\"example-staging-111\"}}}]}]}],\"targetGroups\":[{\"name\":{\"prestaging\":\"example-prestaging-111\",\"staging\":\"example-staging-111\"},\"protocol\":\"HTTP\",\"port\":80,\"healthCheck\":{\"protocol\":\"HTTP\",\"port\":80,\"path\":\"/\",\"interval\":30,\"timeout\":5,\"healthyThreshold\":5,\"unhealthyThreshold\":2,\"matcher\":{\"HttpCode\":200}}}]},\"ecs\":{\"service\":{\"cluster\":{\"prestaging\":\"testing-prestaging\",\"staging\":\"testing-prestaging\"},\"name\":\"example1\",\"allowExisting\":false,\"scalableTarget\":{\"ServiceNamespace\":\"ecs\",\"ResourceId\":{\"prestaging\":\"service/testing-prestaging/example1\",\"staging\":\"service/testing-prestaging/example1\"},\"ScalableDimension\":\"ecs:service:DesiredCount\",\"MinCapacity\":{\"prestaging\":1,\"staging\":1},\"MaxCapacity\":50},\"scalingPolicy\":{\"PolicyName\":{\"prestaging\":\"example-prestaging-1\",\"staging\":\"example-staging-1\"},\"PolicyType\":\"TargetTrackingScaling\",\"ResourceId\":{\"prestaging\":\"service/testing-prestaging/example1\",\"staging\":\"service/testing-prestaging/example1\"},\"ScalableDimension\":\"ecs:service:DesiredCount\",\"ServiceNamespace\":\"ecs\",\"TargetTrackingScalingPolicyConfiguration\":{\"PredefinedMetricSpecification\":{\"PredefinedMetricType\":\"ECSServiceAverageCPUUtilization\"},\"TargetValue\":75,\"ScaleInCooldown\":600,\"ScaleOutCooldown\":60}},\"launchType\":\"FARGATE\",\"desiredCount\":{\"prestaging\":1,\"staging\":\"auto\"},\"healthCheckGracePeriod\":30,\"enableExecuteCommand\":{\"prestaging\":true,\"staging\":true},\"networkConfiguration\":{\"awsvpcConfiguration\":{\"securityGroups\":{\"prestaging\":[\"sg-0567c6c0c02a0abc8\"],\"staging\":[\"sg-0f006bbaeffad9e6d\"]},\"subnets\":{\"prestaging\":[\"subnet-fce4f5c0\",\"subnet-d17219fd\",\"subnet-f8bd4c9c\",\"subnet-fdb6d5a7\",\"subnet-7ccfe234\",\"subnet-c43341c8\"],\"staging\":[\"subnet-1de9466b\",\"subnet-4c3dfb14\",\"subnet-e3c555de\",\"subnet-60cf3d4a\"]},\"assignPublicIp\":\"DISABLED\"}},\"loadBalancers\":[{\"loadBalancerName\":{\"prestaging\":\"example-lb-int-prestaging\",\"staging\":\"example-lb-int-staging\"},\"containerName\":\"example\",\"containerPort\":80,\"targetGroup\":{\"name\":{\"prestaging\":\"example-prestaging-111\",\"staging\":\"example-staging-111\"},\"allowExisting\":false}}]},\"taskDefinition\":{\"family\":\"example\",\"containerDefinitions\":[{\"name\":\"example\",\"image\":\"nginxdemos/hello\",\"essential\":true,\"environment\":[{\"name\":\"CLOUD_ENV\",\"value\":{\"prestaging\":\"steelix\",\"staging\":\"staging\"}}],\"secrets\":[{\"name\":\"CLARI_LOG_LEVEL\",\"valueFrom\":{\"prestaging\":\"arn:aws:secretsmanager:us-east-1:374926383693:secret:/example/prestaging/secrets-PDM7uK:CLARI_LOG_LEVEL::\",\"staging\":\"arn:aws:secretsmanager:us-east-1:374926383693:secret:/example/prestaging/secrets-PDM7uK:CLARI_LOG_LEVEL::\"}}],\"logConfiguration\":{\"logDriver\":\"awsfirelens\",\"options\":{\"Format\":\"json_lines\",\"Header\":{\"prestaging\":\"X-Sumo-Category ECS/prestaging/example\",\"staging\":\"X-Sumo-Category ECS/staging/example\"},\"Host\":\"endpoint1.collection.us2.sumologic.com\",\"Name\":\"http\",\"Port\":\"443\",\"tls\":\"on\",\"tls.verify\":\"off\"},\"secretOptions\":[{\"name\":\"URI\",\"valueFrom\":{\"prestaging\":\"arn:aws:secretsmanager:us-east-1:374926383693:secret:shared/all/infra/non-production_deployment-5T6M2f:SUMOLOGIC_HTTP_SOURCE_URI::\",\"staging\":\"arn:aws:secretsmanager:us-east-1:374926383693:secret:shared/all/infra/non-production_deployment-5T6M2f:SUMOLOGIC_HTTP_SOURCE_URI::\"}}]},\"portMappings\":[{\"protocol\":\"tcp\",\"containerPort\":80}],\"privileged\":false,\"readonlyRootFilesystem\":false,\"dockerLabels\":{\"com.datadoghq.ad.instances\":\"[{\\\"host\\\": \\\"%%host%%\\\", \\\"port\\\": 8080}]\",\"com.datadoghq.ad.check_names\":\"[\\\"nginx\\\"]\"}},{\"name\":\"laceworks-sidecar\",\"image\":\"lacework/datacollector:latest-sidecar\",\"essential\":false,\"environment\":[{\"name\":\"LaceworkVerbose\",\"value\":\"true\"}],\"logConfiguration\":{\"logDriver\":\"awslogs\",\"options\":{\"awslogs-region\":\"us-east-1\",\"awslogs-stream-prefix\":\"ecs\",\"awslogs-group\":{\"prestaging\":\"/aws/ecs/prestaging/example\",\"staging\":\"/aws/ecs/staging/example\"}}},\"cpu\":64,\"memory\":64,\"portMappings\":[],\"readonlyRootFilesystem\":false},{\"name\":\"datadog-agent\",\"image\":\"public.ecr.aws/datadog/agent:7.42.0\",\"essential\":true,\"environment\":[{\"name\":\"ECS_FARGATE\",\"value\":\"true\"}],\"secrets\":[{\"name\":\"DD_API_KEY\",\"valueFrom\":{\"prestaging\":\"arn:aws:secretsmanager:us-east-1:374926383693:secret:shared/all/infra/non-production_deployment-5T6M2f:DATADOG_API_KEY::\",\"staging\":\"arn:aws:secretsmanager:us-east-1:374926383693:secret:shared/all/infra/non-production_deployment-5T6M2f:DATADOG_API_KEY::\"}}],\"logConfiguration\":{\"logDriver\":\"awslogs\",\"options\":{\"awslogs-region\":\"us-east-1\",\"awslogs-stream-prefix\":\"ecs\",\"awslogs-group\":{\"prestaging\":\"/aws/ecs/prestaging/example\",\"staging\":\"/aws/ecs/staging/example\"}}},\"cpu\":128,\"memory\":200,\"portMappings\":[],\"readonlyRootFilesystem\":false},{\"name\":\"log_router_sumo\",\"image\":\"public.ecr.aws/aws-observability/aws-for-fluent-bit:latest\",\"essential\":true,\"firelensConfiguration\":{\"options\":{\"enable-ecs-log-metadata\":\"true\"},\"type\":\"fluentbit\"},\"logConfiguration\":{\"logDriver\":\"awslogs\",\"options\":{\"awslogs-region\":\"us-east-1\",\"awslogs-stream-prefix\":\"ecs\",\"awslogs-group\":{\"prestaging\":\"/aws/ecs/prestaging/example\",\"staging\":\"/aws/ecs/staging/example\"}}},\"cpu\":64,\"memory\":64,\"portMappings\":[],\"readonlyRootFilesystem\":false,\"user\":\"0\"}],\"executionRoleArn\":{\"prestaging\":\"arn:aws:iam::374926383693:role/example_prestaging_ecs_TER\",\"staging\":\"arn:aws:iam::374926383693:role/example_staging_ecs_TER\"},\"taskRoleArn\":{\"prestaging\":\"arn:aws:iam::374926383693:role/example_prestaging_ecs_TR\",\"staging\":\"arn:aws:iam::374926383693:role/example_staging_ecs_TR\"},\"requiresCompatibilities\":[\"FARGATE\"],\"networkMode\":\"awsvpc\",\"memory\":{\"prestaging\":\"512mb\",\"staging\":\"1gb\"},\"cpu\":{\"prestaging\":\"0.25 vCPU\",\"staging\":\"0.5 vCPU\"}}}},\"verification\":{\"request\":{\"method\":\"GET\",\"url\":{\"prestaging\":\"https://internal-frontend-lb-int-prestaging-106928296.us-east-1.elb.amazonaws.com/\",\"staging\":\"https://internal-frontend-lb-int-staging-524940076.us-east-1.elb.amazonaws.com/\"},\"headers\":{\"prestaging\":[\"host: example1.prestaging.clari.com\"],\"staging\":[\"host: example1.staging.clari.com\"]}},\"response\":{\"status\":200,\"body\":\"/buildVersion:[ ]+\\\"${BUILD_VERSION}\\\"/\"}}}\n",
    "environment": "prestaging"
}
```

## Service is not running!

The most common scenario that you will encounter is that a service needs to be torn down and redeployed. Because ECS will automatically try to maintain a set number of services, you will still need to diagnose _why_ the service has started failing. It could been that an image is no longer available, some downstream endpoints are no longer responding, changes to networking permission boundaries, changes to IAM permissions, or secrets that have been invalidated. Once you diagnose the issue, you will likely need to make changes to the service spec to reflect the new service requirements. (`gateways/gw1_spec.json` and/or `gateways/gw5_spec.json`)  

First being by following the steps under `Deleting a service` to tear down the old service. You'll then make your changes to the service spec and (re)deploy the service following the steps under `Deploying a new service`.

Sometimes you'll need to deploy a new instance of the service in parallel before tearing down the old one. Make a copy of one of the service specs. (`cp gateways/gw1_spec.json gateways/gw5_spec.json`). Update any references in the service spec from `1` to `5`. Following the steps under `Deploying a new service` while pointing to your new spec (`gateways/gw5_spec.json`), then the steps under `Deleting a service` while pointing to `gateways/gw5_spec.json`.

## Deploying a new service
`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast create_ecs_task_definition --environment prestaging --output-file /tmp/deployment.json --service-spec-url $SPEC_URL --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})"`

The output from the previous step will have the ARN of the task definition. Copy and paste it into the next line.

`export TASK_DEFINITION_ARN=<TASK_DEFINITION_ARN>`

`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast create_elb_target_groups --environment prestaging --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})"`

`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast update_elb_listeners --environment prestaging --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})"`

`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast create_ecs_service --environment prestaging --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})" --task-definition-arn ${TASK_DEFINITION_ARN} --poll-interval 10 --output-file /tmp/create-service.json`

(Optional)
`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast scale_ecs_service --environment prestaging --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})" --poll-interval 10 --desired-count 1`

## Deleting a service
`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast scale_ecs_service --environment prestaging --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})" --poll-interval 10 --desired-count 0`

`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast delete_ecs_service --environment prestaging --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})" --poll-interval 10`

`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast delete_elb_listeners --environment prestaging --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})"`

`docker run -v $LOCAL_AWS_CREDS:/root/.aws --init --rm mast delete_elb_target_groups --environment prestaging --cloud-spec-json "$(cat ${PATH_TO_SPEC_JSON})"`


### Troubleshooting
ECS is fairly good at giving you specific error messages.  
First look at ECS->Clusters. Pick your cluster and look for the service name. (Both will be in the service spec).  
If the deployment is failing for some reason, click on Tasks and select "Stopped Tasks". Clicking on one of these stopped tasks will usually display an error message at the top for why deployment is failing.  
If the task is Running, but the Target group health check is failing, this is likely due to security groups. If you've ruled out network errors, then you'll need to troubleshoot why your application is not starting. This can also be due to insufficient resources which will not always be obvious or missing environment variables/secrets. Check Cloudwatch logs for hints. Cloudwatch loggroup can also be found in the service spec.
