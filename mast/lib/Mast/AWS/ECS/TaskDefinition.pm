package Mast::AWS::ECS::TaskDefinition;

use v5.030;
use warnings;
no warnings 'uninitialized';

use Carp 'confess';
use AWS::CLIWrapper;

use Mast::Cloud::Metadata '$cloud_spec_url_tag';

my @required = qw(
  family containerDefinitions executionRoleArn taskRoleArn requiresCompatibilities
  memory cpu networkMode
);

sub new {
  my ($class, %params) = @_;

  if (not $params{arn}) {
    for my $prop (@required) {
      confess "ECS task definition $prop property is required"
        unless $params{$prop};
    }
  }
  
  my $aws_region = $params{aws_region};
  my $poll_interval = delete $params{poll_interval} // 10;

  my $aws = delete $params{aws};
  $aws //= AWS::CLIWrapper->new(
      region => $aws_region,
      croak_on_error => 1,
  );

  bless { aws => $aws, poll_interval => $poll_interval, %params }, $class;
}

sub describe {
  my ($self) = @_;

  return $self->{_task_def} if $self->{_task_def};

  my $res = $self->{aws}->ecs('describe-task-definition', {
    'task-definition' => $self->{arn},
    include => ['TAGS'],
  });

  $self->{_task_def} = $res->{taskDefinition};
}

sub create {
  my ($self, %params) = @_;

  my $spec_url = $params{cloud_spec_url};

  my %task_def_payload = (
    family => $self->{family},
    containerDefinitions => $self->{containerDefinitions},
    executionRoleArn => $self->{executionRoleArn},
    memory => $self->{memory},
    cpu => $self->{cpu},
    requiresCompatibilities => $self->{requiresCompatibilities},
    taskRoleArn => $self->{taskRoleArn},
    networkMode => $self->{networkMode},
    volumes => $self->{volumes} // [],
    $spec_url ? (tags => [{ key => $cloud_spec_url_tag, value => $spec_url }]) : (),
  );

  my $res = $self->{aws}->ecs('register-task-definition', {
    'cli-input-json' => JSON->new->encode(\%task_def_payload),
  });

  $self->{_task_def} = $res->{taskDefinition};

  return $self->{arn} = $self->{_task_def}->{taskDefinitionArn};
}

# Cannot use delete keyword
sub remove {
  my ($self) = @_;

  confess "Cannot delete task definition $self->{arn}, it does not exist"
    unless $self->describe;
  
  $self->{aws}->ecs('deregister-task-definition', {
    'task-definition' => $self->{arn},
  });

  undef $self->{_task_def};

  return 1;
}