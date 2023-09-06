{
  aws => {
    region => 'us-east-1',
  },
  elb => {
    loadBalancers => [{
      type => 'application',
      name => 'frontend-lb-int-prestaging',
      securityGroups => ['sg-0f8cca4c407546a36'],
      listeners => [{
        protocol => 'HTTPS',
        port => 443,
        rules => {
          standby => [{
            placement => 'start',
            conditions => [
              { Field => 'path-pattern', Values => ['/api/baz'] },
              { Field => 'http-header',
                HttpHeaderConfig => {
                  HttpHeaderName => 'apollographql-client-version',
                  Values => ['master-barbazoo']
                },
              },
            ],
            action => {
              type => 'forward',
              targetGroupName => 'foo-gql-pres-master-barbazoo',
            },
          }],
          active => [{
            placement => 'start',
            conditions => [
              { Field => 'path-pattern', Values => ['/api/baz'] },
              { Field => 'http-header',
                HttpHeaderConfig => {
                  HttpHeaderName => 'apollographql-client-version',
                  Values => ['master-barbazoo']
                },
              },
            ],
            action => {
              type => 'forward',
              targetGroupName => 'foo-gql-pres-master-barbazoo',
            },
          }],
        },
      }],
    }],
    targetGroups => [{
      name => 'foo-gql-pres-master-barbazoo',
      protocol => 'HTTP',
      port => 4000,
      healthCheck => {
        protocol => 'HTTP',
        port => 4000,
        path => '/ping',
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
      cluster => 'frontend-prestaging',
      name => 'baz-master-barbazoo',
      launchType => 'FARGATE',
      desiredCount => 2,
      healthCheckGracePeriod => 30,
      enableExecuteCommand => JSON::PP::true,
      networkConfiguration => {
        awsvpcConfiguration => {
          securityGroups => ["sg-0d7e69bc88949868f"],
          subnets => [
            "subnet-fce4f5c0",
            "subnet-d17219fd",
            "subnet-f8bd4c9c",
            "subnet-fdb6d5a7",
            "subnet-7ccfe234",
            "subnet-c43341c8",
          ],
          assignPublicIp => 'DISABLED',
        },
      },
      loadBalancers => [{ 
        loadBalancerName => 'frontend-lb-int-prestaging',
        containerName => 'baz',
        containerPort => 4000,
        targetGroup => {
          name => 'foo-gql-pres-master-barbazoo',
          allowExisting => JSON::PP::false,
        },
      }],
    },
    taskDefinition => {
      family => "baz",
      containerDefinitions => [{
        name => 'baz',
        image => 'foous.jfrog.io/foo-docker-v0-virtual/foo/baz:master-barbazoo',
        essential => JSON::PP::true,
        environment => [
          { name => 'STAGE', value => 'steelix' },
          { name => 'GATEWAY_HOST', value => 'https://gateway-steelix.foo.com' },
          { name => 'HTTP_CLIENT_TIMEOUT', value => '10000' },
          { name => 'GRAPHQL_CONSOLE_LOG_LEVEL', value => 'info' },
          { name => 'APOLLO_GRAPH_VARIANT', value => 'steelix' },
          { name => 'APOLLO_SCHEMA_REPORTING', value => 'true' },
        ],
        secrets => [
          { name => 'APOLLO_KEY', valueFrom => 'arn:aws:secretsmanager:us-east-1:123456789:secret:prestaging/nexus/config-St1c4l:APOLLO_KEY::' },
        ],
        portMappings => [
          { protocol => 'tcp', containerPort => 4000 },
        ],
        privileged => JSON::PP::false,
        readonlyRootFilesystem => JSON::PP::false,
      }],
      executionRoleArn => 'arn:aws:iam::123456789:role/foo_graphql_prestaging_ecs_TER',
      taskRoleArn => 'arn:aws:iam::123456789:role/foo_graphql_prestaging_ecs_TR',
      networkMode => 'awsvpc',
      requiresCompatibilities => ['FARGATE'],
      memory => '1024',
      cpu => '256',
    },
  },
  verification => {
    request => {
      method => 'POST',
      url => "https://internal-frontend-lb-int-prestaging.us-east-1.elb.amazonaws.com/api/baz",
      headers => [
        "content-type: application/json",
        "apollographql-client-version: master-barbazoo"
      ],
      body => '{"query":"{refresh{graphqlVersion}}"}',
    },
    response => {
      status => [200],
      body => '{"data":{"refresh":{"graphqlVersion":"master-barbazoo"}}}'
    },
  },
};
