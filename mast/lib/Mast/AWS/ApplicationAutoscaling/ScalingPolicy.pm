package Mast::AWS::ApplicationAutoscaling::ScalingPolicy;

use v5.030;
use warnings;
no warnings 'uninitialized';

use Carp 'confess';
use JSON::PP;
use AWS::CLIWrapper;

use Mast::AWS::ELB::LoadBalancer;
use Mast::AWS::ELB::TargetGroup;

sub new {
  my ($class, %params) = @_;

  $params{service_namespace} //= 'ecs';

  confess "Policy name is required"
    unless defined $params{policy_name};

  my $aws_region = delete $params{aws_region};

  my $aws = delete $params{aws};
  $aws //= AWS::CLIWrapper->new(
      region => $aws_region,
      croak_on_error => 1,
  );

  bless { aws => $aws, %params }, $class;
}

sub describe {
  my ($self, $force) = @_;

  my $scaling_policy = do {
    my $res = $self->{aws}->application_autoscaling('describe-scaling-policies', {
      'service-namespace' => $self->{service_namespace},
      'policy-names' => [$self->{policy_name}],
      'max-items' => 1,
    });

    $res->{ScalingPolicies}->[0];
  };

  return $scaling_policy;
}

sub create {
  my ($self, %params) = @_;

  my ($policy) = @params{qw(scaling_policy)};

  if ($policy->{PolicyType} eq 'TargetTrackingScaling') {
    my $metric_spec
      = $policy->{TargetTrackingScalingPolicyConfiguration}->{PredefinedMetricSpecification};
    
    if ($metric_spec->{PredefinedMetricType} eq 'ALBRequestCountPerTarget') {
      my $label = $metric_spec->{ResourceLabel};

      my ($lb_name, $tg_name) = @$label{qw(loadBalancerName targetGroupName)};

      my $lb = Mast::AWS::ELB::LoadBalancer->new(
        aws_region => $self->{aws_region},
        aws => $self->{aws},
        name => $lb_name,
      );

      my $lb_id = $lb->id_for_autoscaling;

      my $tg = Mast::AWS::ELB::TargetGroup->new(
        aws_region => $self->{aws_region},
        aws => $self->{aws},
        name => $tg_name,
      );

      my $tg_id = $tg->id_for_autoscaling;

      $metric_spec->{ResourceLabel} = "$lb_id/$tg_id";
    }
  }

  my $put_res = $self->{aws}->application_autoscaling('put-scaling-policy', {
    "cli-input-json" => encode_json $policy,
  });

  return $put_res;
}

sub remove {
  my ($self, %params) = @_;

  my $del_res = eval {
    $self->{aws}->application_autoscaling('delete-scaling-policy', {
      "cli-input-json" => $params{cli_input_json}
    });
  };
  # TODO: This handling shouldn't happen here. We need to validate the ExecutionPlan and infra before generating steps
  if($@){
    if($@ !~ /ObjectNotFoundException/){
      confess $@;
    } else {
      say "skipping, because scaling_policy not found. this could be an indication that something is wrong.";
    }
  }
  return 1;
}

1;
