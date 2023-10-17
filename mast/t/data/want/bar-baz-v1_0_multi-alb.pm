{
  version => '1.0',
  deploy => {
    provider => 'harness',
    harnessConfiguration => {
      pipeline => 'foo-foo',
      triggerUrl => 'https://app.harness.io/gateway/api/webhooks/foo-foo?accountId=peSAz-_HRnyg80J_7dFk2g',
    },
  },
  aws => {
    region => 'us-east-1',
    elb => {
      loadBalancers => [{
        type => 'application',
        name => 'cluster-lb-int-staging',
        securityGroups => ['sg-alb-staging'],
        listeners => [{
          protocol => 'HTTPS',
          port => 444,
          rules => [{
            placement => 'end',
            conditions => [
              { Field => 'host-header', Values => ["foo.staging.foo.com"] },
            ],
            action => {
              type => 'forward',
              targetGroupName => 'clr-foo-stag-master-foobaroo',
            },
          }],
        }],
      }, {
        type => 'application',
        name => 'cluster-lb-int-staging',
        securityGroups => ['sg-alb-staging'],
        listeners => [{
          protocol => 'HTTPS',
          port => 443,
          rules => [{
            placement => 'end',
            conditions => [
              { Field => 'host-header', Values => ["foo.staging.foo.com"] },
            ],
            action => {
              type => 'forward',
              targetGroupName => 'clr-foo-stag-master-foobaroo',
            },
          }],
        }],
      }],
      targetGroups => [{
        name => 'clr-foo-stag-master-foobaroo',
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
        name => 'foo-foo-master-foobaroo',
        launchType => 'FARGATE',
        desiredCount => 1,
        healthCheckGracePeriod => 30,
        enableExecuteCommand => JSON::PP::true,
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
            name => 'clr-foo-stag-master-foobaroo',
            allowExisting => JSON::PP::false,
          },
          containerName => 'foo-foo',
          containerPort => 4321,
        }],
      },
      taskDefinition => {
        family => "foo-foo",
        containerDefinitions => [{
          name => 'foo-foo',
          image => 'foo/foo-foo:master-foobaroo',
          essential => JSON::PP::true,
          environment => [
            { name => 'STAGE', value => 'staging' },
            { name => 'FOO', value => 'baz' },
          ],
          secrets => [
            { name => 'SECRET', valueFrom => 'arn:aws:secretsmanager:us-east-1:12345678901:secret:staging/foo-foo/config:SECRET::' },
            { name => 'API_KEY', valueFrom => 'arn:aws:secretsmanager:us-east-1:12345678901:secret:staging/foo-foo/api_keys:API_KEY::' },
          ],
          logConfiguration => {
            logDriver => 'awsfirelens',
            options => {
              Format => 'json_lines',
              Header => 'X-Sumo-Category ECS/staging/foo-foo',
              Host => 'endpoint1.collection.us2.sumologic.com',
              Name => 'http',
              Port => '443',
              tls => 'on',
              'tls.verify' => 'off',
            },
            secretOptions => [
              { name => 'URI', valueFrom => 'arn:aws:secretsmanager:us-east-1:12345678901:secret:infra/staging/deployment:SUMOLOGIC_HTTP_SOURCE_URI::' },
            ],
          },
          portMappings => [
            { protocol => 'tcp', containerPort => 4321 },
          ],
          privileged => JSON::PP::false,
          readonlyRootFilesystem => JSON::PP::false,
          repositoryCredentials => {
            credentialsParameter => 'arn:aws:secretsmanager:us-east-1:12345678901:secret:foo_dockerhub_foodeploy-aKXqDz'
          },
        }, {
          name => 'laceworks-sidecar',
          image => 'foo/lacework:latest',
          essential => JSON::PP::false,
          environment => [
            { name => 'LaceworkVerbose', value => 'true' },
          ],
          logConfiguration => {
            logDriver => 'awslogs',
            options => {
              'awslogs-region' => 'us-east-1',
              'awslogs-stream-prefix' => 'ecs',
              'awslogs-group' => '/aws/ecs/staging/foo-foo',
            },
          },
          repositoryCredentials => {
            credentialsParameter => 'arn:aws:secretsmanager:us-east-1:12345678901:secret:foo_dockerhub_foodeploy-aKXqDz'
          },
          cpu => 64,
          memory => 64,
          portMappings => [],
          readonlyRootFilesystem => JSON::PP::false,
        }, {
          name => 'datadog-agent',
          image => 'foo/datadog-agent:latest',
          essential => JSON::PP::true,
          environment => [
            { name => 'ECS_FARGATE', value => 'true' },
          ],
          secrets => [
            { name => 'DD_API_KEY', valueFrom => 'arn:aws:secretsmanager:us-east-1:12345678901:secret:infra/staging/deployment:DATADOG_API_KEY::' },
          ],
          logConfiguration => {
            logDriver => 'awslogs',
            options => {
              'awslogs-region' => 'us-east-1',
              'awslogs-stream-prefix' => 'ecs',
              'awslogs-group' => '/aws/ecs/staging/foo-foo',
            },
          },
          repositoryCredentials => {
            credentialsParameter => 'arn:aws:secretsmanager:us-east-1:12345678901:secret:foo_dockerhub_foodeploy-aKXqDz'
          },
          cpu => 128,
          memory => 128,
          portMappings => [],
          readonlyRootFilesystem => JSON::PP::false,
        }, {
          name => 'log_router_sumo',
          image => 'amazon/aws-for-fluent-bit:latest',
          essential => JSON::PP::true,
          firelensConfiguration => {
            type => 'fluentbit',
            options => {
              'enable-ecs-log-metadata' => 'true'
            },
          },
          logConfiguration => {
            logDriver => 'awslogs',
            options => {
              'awslogs-region' => 'us-east-1',
              'awslogs-stream-prefix' => 'ecs',
              'awslogs-group' => '/aws/ecs/staging/foo-foo',
            },
          },
          repositoryCredentials => {
            credentialsParameter => 'arn:aws:secretsmanager:us-east-1:12345678901:secret:foo_dockerhub_foodeploy-aKXqDz'
          },
          cpu => 64,
          memory => 64, 
          portMappings => [],
          readonlyRootFilesystem => JSON::PP::false,
          user => '0',
        }],
        executionRoleArn => 'arn:aws:iam::12345678901:role/foo_foo_staging_ecs_TER',
        taskRoleArn => 'arn:aws:iam::12345678901:role/foo_foo_staging_ecs_TR',
        networkMode => 'awsvpc',
        requiresCompatibilities => ['FARGATE'],
        memory => '2048',
        cpu => '1024',
      },
      tasks => {
        standbySmokeTest => {
          cluster => 'frontend-staging',
          desiredCount => 1,
          launchType => 'FARGATE',
          taskDefinition => {
            family => 'frontend-staging-smoke-test',
            containerDefinitions => [{
              name => 'end2end-tests',
              image => 'foo/end2end-tests:latest',
              essential => JSON::PP::true,
              logConfiguration => {
                logDriver => 'awslogs',
                options => {
                  'awslogs-region' => 'us-east-1',
                  'awslogs-stream-prefix' => 'ecs',
                  'awslogs-group' => '/ecs/end2end-smoke-tests',
                },
              },
              environment => [{
                name => 'appUrl', value => 'https://app-test.staging.foo.com',
              }, {
                name => 'cloud_env', value => 'staging',
              }],
              secrets => [{
                name => 'someSecret',
                valueFrom => "arn:aws:secretsmanager:us-east-1:123456:secret:staging/end2end-tests/config:SECRET::",
              }],
              command => ['/run-tests.sh'],
            }],
            memory => '4096',
            cpu => '2048',
            requiresCompatibilities => 'FARGATE',
            networkMode => "awsvpc",
            executionRoleArn => "arn:aws:iam::123456:role/foo_foo_staging_ecs_TER",
            taskRoleArn => "arn:aws:iam::123456:role/foo_foo_staging_ecs_TR",
          },
          networkConfiguration => {
            awsvpcConfiguration => {
              securityGroups => ["sg-foo", "sg-bar"],
              subnets => ["subnet-blerg", "subnet-throbbe"],
              assignPublicIp => "DISABLED",
            }
          },
        },
      },
    },
  },
  verification => {
    request => {
      method => 'GET',
      url => 'https://internal-cluster-lb-int-staging.us-east-1.elb.amazonaws.com/foo-foo',
      headers => [
        'host: standby.foo.staging.foo.com',
      ],
    },
    response => {
      status => [200],
      body => '/buildVersion:\s+"master-foobaroo"/',
    },
  },
};