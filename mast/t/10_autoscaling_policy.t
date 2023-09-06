use v5.030;
use warnings;
no warnings 'uninitialized';

use Test::More;
use File::Slurp;
use JSON::PP;

use Mast::AWS::ApplicationAutoscaling::ScalingPolicy;

use lib 't/lib';
use AWS::MockCLIWrapper;

my $aws_region = 'us-east-1';
my $tests = eval join '', <DATA> or die "$@";

for my $test (@$tests) {
  my ($name, $policy, $lb_response, $tg_response, $want)
    = @$test{qw(name policy lb_response tg_response want)};

  my $aws = AWS::MockCLIWrapper->new(
    aws_region => $aws_region,
    actors => {
      elbv2 => {
        'describe-load-balancers' => sub {
          return {
            LoadBalancers => [$lb_response],
          };
        },
        'describe-target-groups' => sub {
          return {
            TargetGroups => [$tg_response],
          };
        },
      },
      application_autoscaling => {
        'put-scaling-policy' => sub {
          my ($self, $params) = @_;

          my $input = decode_json $params->{'cli-input-json'};

          is_deeply $input, $want, "$name aws cli input";
        },
      },
    },
  );

  my $autoscaling = Mast::AWS::ApplicationAutoscaling::ScalingPolicy->new(
    aws_region => $aws_region,
    aws => $aws,
    policy_name => $policy->{PolicyName},
  );

  eval { $autoscaling->create(scaling_policy => $policy) };

  is "$@", "", "$name no exception";
}

done_testing;

__DATA__
# line 49
[{
  name => "ECSServiceAverageCPUUtilization",
  policy => {
    PolicyName => "foo",
    PolicyType => "TargetTrackingScaling",
    ResourceId => "service/foo-staging/foo",
    ScalableDimension => "ecs:service:DesiredCount",
    ServiceNamespace => "ecs",
    TargetTrackingScalingPolicyConfiguration => {
      PredefinedMetricSpecification => {
        PredefinedMetricType => "ECSServiceAverageCPUUtilization",
      },
      TargetValue => 75,
      ScaleInCooldown => 600,
      ScaleOutCooldown => 60,
    },
  },
  want => {
    PolicyName => "foo",
    PolicyType => "TargetTrackingScaling",
    ResourceId => "service/foo-staging/foo",
    ScalableDimension => "ecs:service:DesiredCount",
    ServiceNamespace => "ecs",
    TargetTrackingScalingPolicyConfiguration => {
      PredefinedMetricSpecification => {
        PredefinedMetricType => "ECSServiceAverageCPUUtilization",
      },
      TargetValue => 75,
      ScaleInCooldown => 600,
      ScaleOutCooldown => 60,
    },
  },
}, {
  name => "ALBRequestCountPerTarget",
  policy => {
    PolicyName => "bar",
    PolicyType => "TargetTrackingScaling",
    ResourceId => "service/foo-staging/bar",
    ScalableDimension => "ecs:service:DesiredCount",
    ServiceNamespace => "ecs",
    TargetTrackingScalingPolicyConfiguration => {
      PredefinedMetricSpecification => {
        PredefinedMetricType => "ALBRequestCountPerTarget",
        ResourceLabel => {
          loadBalancerName => "lb-bar",
          targetGroupName => "tg-bar-staging",
        },
      },
      TargetValue => 1000,
      ScaleInCooldown => 600,
      ScaleOutCooldown => 60,
    },
  },
  lb_response => {
    LoadBalancerArn => 'arn:aws:elasticloadbalancing:us-east-1:12345678:loadbalancer/app/lb-bar/123456',
  },
  tg_response => {
    TargetGroupArn => 'arn:aws:elasticloadbalancing:us-east-1:12345678:targetgroup/tg-bar-staging/654321',
  },
  want => {
    PolicyName => "bar",
    PolicyType => "TargetTrackingScaling",
    ResourceId => "service/foo-staging/bar",
    ScalableDimension => "ecs:service:DesiredCount",
    ServiceNamespace => "ecs",
    TargetTrackingScalingPolicyConfiguration => {
      PredefinedMetricSpecification => {
        PredefinedMetricType => "ALBRequestCountPerTarget",
        ResourceLabel => "app/lb-bar/123456/targetgroup/tg-bar-staging/654321",
      },
      TargetValue => 1000,
      ScaleInCooldown => 600,
      ScaleOutCooldown => 60,
    },
  },
}]
