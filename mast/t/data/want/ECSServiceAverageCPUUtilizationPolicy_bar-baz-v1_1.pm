{
  version => '1.1',
  aws => {
    region => 'us-east-1',
    elb => {
      loadBalancers => [{
        type => 'application',
        name => 'cluster-lb-int-staging',
        securityGroups => ['sg-alb-staging'],
        listeners => [{
          protocol => 'HTTPS',
          port => 443,
          rules => {
            standby => [{
              placement => 'end',
              conditions => [
                { Field => 'host-header', Values => ["standby.staging.foo.com"] },
              ],
              action => {
                type => 'forward',
                targetGroupName => 'foo-staging-foobaroo',
              },
            }],
            active => [{
              placement => 'end',
              conditions => [
                { Field => 'host-header', Values => ["staging.foo.com"] },
              ],
              action => {
                type => 'forward',
                targetGroupName => 'foo-staging-foobaroo',
              },
            }],
          },
        }],
      }],
      targetGroups => [{
        name => 'foo-staging-foobaroo',
        protocol => 'HTTPS',
        port => 4321,
        healthCheck => {
          protocol => 'HTTPS',
          port => 4321,
          path => '/',
          interval => 30,
          timeout => 5,
          healthyThreshold => 5,
          unhealthyThreshold => 2,
          matcher => {
            HttpCode => 200,
          },
        },
      }],
    },
    ecs => {
      service => {
        cluster => 'cluster-staging',
        name => 'foo-foobaroo',
        launchType => 'FARGATE',
        desiredCount => 1,
        healthCheckGracePeriod => 30,
        enableExecuteCommand => JSON::PP::true,
        scalableTarget => {
          ServiceNamespace => 'ecs',
          ResourceId => "service/cluster-staging/foo-foobaroo",
          ScalableDimension => "ecs:service:DesiredCount",
          MinCapacity => 1,
          MaxCapacity => 5,
        },
        scalingPolicy => {
          PolicyName => "foo-example-ssfdgsdfgsdfg",
          PolicyType => "TargetTrackingScaling",
          ResourceId => "service/cluster-staging/foo-foobaroo",
          ScalableDimension => "ecs:service:DesiredCount",
          ServiceNamespace => "ecs",
          TargetTrackingScalingPolicyConfiguration => {
            PredefinedMetricSpecification => {
              PredefinedMetricType => "ECSServiceAverageCPUUtilization"
            },
            TargetValue => 75,
            ScaleInCooldown => 60,
            ScaleOutCooldown => 60
          }
        },
        networkConfiguration => {
          awsvpcConfiguration => {
            securityGroups => ['sg-svc-staging-1', 'sg-svc-staging-2'],
            subnets => ['subnet-staging-1', 'subnet-staging-2'],
            assignPublicIp => 'DISABLED',
          },
        },
        loadBalancers => [{
          loadBalancerName => 'cluster-lb-int-staging',
          targetGroup => {
            name => 'foo-staging-foobaroo',
            allowExisting => JSON::PP::false,
          },
          containerName => 'foo',
          containerPort => 4321,
        }],
      },
      taskDefinition => {
        family => "foo",
        containerDefinitions => [{
          name => 'foo',
          image => 'foo/foo:foobaroo',
          essential => JSON::PP::true,
          environment => [
            { name => 'STAGE', value => 'staging' },
            { name => 'FOO', value => 'baz' },
          ],
          secrets => [
            { name => 'SECRET', valueFrom => 'arn:aws:secretsmanager:us-east-1:123456789:secret:staging/foo/config:SECRET::' },
            { name => 'API_KEY', valueFrom => 'arn:aws:secretsmanager:us-east-1:123456789:secret:staging/foo/api_keys:API_KEY::' },
          ],
          portMappings => [
            { protocol => 'tcp', containerPort => 4321 },
          ],
          privileged => JSON::PP::false,
          readonlyRootFilesystem => JSON::PP::false,
        }],
        executionRoleArn => 'arn:aws:iam::123456789:role/foo_staging_ecs_TER',
        taskRoleArn => 'arn:aws:iam::123456789:role/foo_staging_ecs_TR',
        networkMode => 'awsvpc',
        requiresCompatibilities => ['FARGATE'],
        memory => '2048',
        cpu => '1024',
      },
    },
  },
  verification => {
    request => {
      method => 'GET',
      url => 'https://internal-cluster-lb-int-staging.us-east-1.elb.amazonaws.com/foo',
      headers => [
        'host: standby.staging.foo.com',
      ],
    },
    response => {
      status => [200],
      body => '/buildVersion:\s+"master-foobaroo"/',
    },
  },
};
