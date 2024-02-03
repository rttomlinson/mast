package Mast::Deploy::TaskDefinition;

use v5.030;

use warnings;
no warnings 'uninitialized', 'unopened';

####
## LOGGING CONFIG START
####
use Mast::CustomLogger qw(lambda_say lambda_confess lambda_die);
####
## LOGGING CONFIG END
####

use Carp 'confess';

use parent 'Mast::Deploy::Base';

use JSON::PP;
use Mast::Cloud::Spec;
use Mast::AWS::ECS::TaskDefinition;

sub create_task_definition {
  my ($self, %params) = @_;
  my ($spec,) = @$self{'spec'};
  my $spec_url = $params{cloud_spec_url};

  lambda_confess "Cloud spec URL is required" unless length $spec_url > 1;

  my $task_def = $spec->ecs->{taskDefinition};
  my $family = $task_def->{family} || $spec->ecs->{service}->{name};

  my $task_def_obj = Mast::AWS::ECS::TaskDefinition->new(
    aws_region => $self->aws_region,
    family => $family,
    containerDefinitions => $task_def->{containerDefinitions},
    executionRoleArn => $task_def->{executionRoleArn},
    memory => $task_def->{memory},
    cpu => $task_def->{cpu},
    requiresCompatibilities => $task_def->{requiresCompatibilities},
    taskRoleArn => $task_def->{taskRoleArn},
    networkMode => $task_def->{networkMode},
    volumes => $task_def->{volumes},
    aws => $self->aws,
  );
  lambda_say("Creating ECS task definition in family $family...");

  my $task_definition_arn = $task_def_obj->create(
    cloud_spec_url => $spec_url
  );
  lambda_say("Successfully created task definition with ARN: $task_definition_arn");

  return $task_definition_arn;
}

sub delete_task_definition {
  my ($self, %params) = @_;

  my $arn = $params{task_definition_arn};

  my $task_def = Mast::AWS::ECS::TaskDefinition->new(
    arn => $arn,
    aws => $self->aws,
  );

  lambda_say("Deleting ECS task definition with ARN $arn...");

  $task_def->remove;

  lambda_say("Successfully deleted task definition with ARN $arn");
}

1;
