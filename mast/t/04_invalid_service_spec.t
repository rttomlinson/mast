use v5.030;
use strictures 2;

use Test::More;
use File::Slurp;

use Mast::Service::Spec;

my $tests = eval join '', <DATA> or die "$@";

for my $test (sort keys %$tests) {
  next if @ARGV and not grep { $_ eq $test } @ARGV;

  my $test_data = $tests->{$test};
  my ($contexts, $spec_from, $xcpt)
    = @$test_data{qw(contexts spec_from exception)};
  $xcpt = qr/$xcpt/ unless 'RegExp' eq ref $xcpt;

  my $service_spec_json = read_file $spec_from;

  eval {
    Mast::Service::Spec->new(
      contexts => $contexts,
      service_spec_json => $service_spec_json
    )
  };

  like "$@", $xcpt, "$test exception ok";
}

done_testing;

__DATA__
# line 35
{
  'invalid-version' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/invalid-version.json',
    exception => qr/Cannot load parser for service spec version foo/,
  },
  'invalid-target-group-name' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/invalid-example.json',
    exception => qr/Invalid target group name/,
  },
  'invalid-scaling-policy-resource-id' => {
    contexts => ['prestaging', 'standby'],
    spec_from => 't/data/spec/scaling-policies-invalid-example.json',
    exception => qr/Scalable Target ResourceId is expected.*?service\/\$cluster_name\/\$service_name/,
  },
  'invalid-example-missing-loadBalancerName' => {
    contexts => ['prestaging', 'active'],
    spec_from => 't/data/spec/ALBRequestCountPerTarget_bar-baz-v1_0_invalid_missing_loadBalancerName1.json',
    exception => qr/Scaling policy for ECS service foo-foobaroo is configured for tracking ALBRequestCountPerTarget metric. The policy is expected to have TargetTrackingScalingPolicyConfiguration.PredefinedMetricSpecification.ResourceLabel property as an object with loadBalancerName and targetGroupName properties in it/,
  },
  'invalid-example-missing-targetGroupName' => {
    contexts => ['prestaging', 'active'],
    spec_from => 't/data/spec/ALBRequestCountPerTarget_bar-baz-v1_0_invalid_missing_targetGroupName.json',
    exception => qr/Scaling policy for ECS service foo-foobaroo is configured for tracking ALBRequestCountPerTarget metric. The policy is expected to have TargetTrackingScalingPolicyConfiguration.PredefinedMetricSpecification.ResourceLabel property as an object with loadBalancerName and targetGroupName properties in it/,
  },
  'missing-type-invalid-example' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/elb/missing-type-elb-ecs-configs.json',
    exception => 'elb.loadBalancer value requires a type keyword',
  },
  'empty-string-type-invalid-example' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/elb/empty-string-type-elb-ecs-configs.json',
    exception => qr/Unsupported type.*in load balancer.*expected.*(network|application)/,
  },
  'null-type-invalid-example' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/elb/null-type-elb-ecs-configs.json',
    exception => qr/Unsupported type.*in load balancer example-lb-int-prestag: expected.*(network|application)/,
  },
  'missing-elb-name-invalid-example' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/elb/missing-name-elb-ecs-configs.json',
    exception => 'elb.loadBalancer value requires a name keyword',
  },
  'null-name-invalid-example' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/elb/null-name-elb-ecs-configs.json',
    exception => 'Invalid load balancer name: null',
  },
  'empty-string-elb-name-invalid-example' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/elb/empty-string-name-elb-ecs-configs.json',
    exception => 'Invalid ELB load balancer name, only alphanumerics and hyphens are permitted',
  },
  'whitespace-string-elb-name-invalid-example' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/elb/empty-string-name-elb-ecs-configs.json',
    exception => 'Invalid ELB load balancer name, only alphanumerics and hyphens are permitted: got ""',
  },
  'non-http-or-https-protocol-on-application-type-invalid-example' => {
    contexts => ['prestaging'],
    spec_from => 't/data/spec/elb/non-http-or-https-protocol-on-application-elb.json',
    exception => 'Invalid listener protocol in application load balancer example-lb-int-prestag: should be HTTP or HTTPS, got TCP',
  },
  "tg-mismatch-in-active-v1_0" => {
    "exception" => qr/Invalid action for listener rule/,
    "spec_from" => "t/data/spec/missing-tg-spec-active_v1_0.json",
    "contexts" => ["prestaging", "active"],
  },
  "tg-mismatch-in-standby-v1_0" => {
    "exception" => qr/Invalid action for listener rule/,
    "spec_from" => "t/data/spec/missing-tg-spec-standby_v1_0.json",
    "contexts" => ["prestaging", "standby"],
  },
  "missing-tg-spec-unknown-tg-in-ecs-lbs_v1_0" => {
    "exception" => qr/Cannot find matching ELB target group configuration for container name/,
    "spec_from" => "t/data/spec/missing-tg-spec-unknown-tg-in-ecs-lbs_v1_0.json",
    "contexts" => ["prestaging", "active"],
  },
  'matching-elb-name-and-listener-ports' => {
    contexts => ['prestaging', 'active'],
    spec_from => 't/data/spec/elb/invalid-repeat-listener-port-bar-baz-v1_0_multi-alb.json',
    exception => 'At least one repeat load balancer and listener port found.',
  },
  'missing-target-group-in-elb-section' => {
    contexts => ['prestaging', 'active'],
    spec_from => 't/data/spec/elb/missing-target-group-in-elb-section-bar-baz-v1_0_multi-alb.json',
    exception => 'Cannot find matching ELB target group configuration for container name',
  },
  # 'same-target-group-cannot-be-on-different-elbs' => {
  #   contexts => ['prestaging', 'active'],
  #   spec_from => 't/data/spec/elb/same-target-group-on-multiple-diff-elbs-bar-baz-v1_0_multi-alb.json',
  #   exception => 'Same target group cannot be on multiple different elbs',
  # },
  'same-load-balancer-and-listener-port-cannot-be-appear' => {
    contexts => ['prestaging', 'active'],
    spec_from => 't/data/spec/elb/invalid-repeat-listener-port-v1_0_multi-alb-multi-listener.json',
    exception => 'At least one repeat load balancer and listener port found.',
  },
  # 'same-target-group-cannot-be-on-different-elbs-multi-listener' => {
  #   contexts => ['prestaging', 'active'],
  #   spec_from => 't/data/spec/elb/invalid-repeat-target-group-v1_0_multi-alb-multi-listener.json',
  #   exception => 'Same target group cannot be on multiple different elbs.',
  # },
  'invalid-v2_0_elb_references_tg_not_found_under_ecs' => {
    contexts => ['prestaging', 'active'],
    spec_from => 't/data/spec/invalid-v1_0_elb_references_tg_not_found_under_ecs.json',
    exception => 'Cannot find matching ELB target group configuration for container name'
  },
  # 'spec2_0_does_not_support_multiple_rules' => {
  #   contexts => ['prestaging', 'active'],
  #   spec_from => 't/data/spec/elb/multiple-rules-multiple-diff-elbs-bar-baz-v1_0_multi-alb.json',
  #   exception => 'version 2.0 of the spec is unable to support multiple rule validation and actions other than forward to targetGroup'
  # },
  
}
