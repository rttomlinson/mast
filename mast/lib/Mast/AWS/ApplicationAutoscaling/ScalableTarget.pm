package Mast::AWS::ApplicationAutoscaling::ScalableTarget;

use v5.030;
use warnings;
no warnings 'uninitialized';

use Carp 'confess';
use JSON::PP;
use AWS::CLIWrapper;

use Mast::AWS::ELB::TargetGroup;

sub new {
  my ($class, %params) = @_;

  $params{service_namespace} //= 'ecs';

  confess "Resource id is required"
    unless defined $params{resource_id};

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

  my $scalable_target = do {
    my $res = $self->{aws}->application_autoscaling('describe-scalable-targets', {
      'service-namespace' => $self->{service_namespace},
      'resource-ids' => [$self->{resource_id}],
      'max-items' => 1,
    });

    $res->{ScalableTargets}->[0];
  };

  return $scalable_target;
}

sub create {
  my ($self, %params) = @_;

  my $register_res = $self->{aws}->application_autoscaling('register-scalable-target', {
    "cli-input-json" => $params{cli_input_json}
  });

  return $register_res;
}

sub remove {
  my ($self, %params) = @_;

  my $deregister_res = eval {
    $self->{aws}->application_autoscaling('deregister-scalable-target', {
      "cli-input-json" => $params{cli_input_json}
    });
  };
  if($@){
    if($@ !~ /ObjectNotFoundException/){
      confess $@;
    } else {
      say "skipping, because scalable_target not found. this could be an indication that something is wrong.";
    }
  }

  return 1;
}

1;
