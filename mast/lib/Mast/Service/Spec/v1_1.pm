package Mast::Service::Spec::v1_1;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use parent 'Mast::Service::Spec::v1_0';

use Carp 'confess';

our @VERSION = (1.1, '1.1');

sub _normalize_ecs {
  my ($self) = @_;

  $self->SUPER::_normalize_ecs;

  my $ecs_tasks = $self->ecs->{tasks};

  # Tasks are optional
  return unless defined $ecs_tasks;

  confess "ecs.tasks is not an object"
    unless 'HASH' eq ref $ecs_tasks;

  $self->_normalize_ecs_tasks($ecs_tasks);
}

sub _normalize_ecs_tasks {
  my ($self, $ecs_tasks) = @_;

  for my $task_name (keys %$ecs_tasks) {
    $self->_normalize_ecs_task($task_name, $ecs_tasks->{$task_name});
  }
}

sub _normalize_tests {
  my ($self) = @_;

  confess "tests section is not supported, use ecs.tasks section instead"
    if exists $self->{spec}->{tests};
}

sub tests {
  my ($self) = @_;

  warn 'tests method is deprecated, use ecs.tasks instead';

  my $ecs_tasks = $self->ecs->{tasks} // {};

  my $tests = {};

  for my $task_name (keys %$ecs_tasks) {
    $tests->{$task_name} = {
      type => 'ecsTask',
      ecsTask => $ecs_tasks->{$task_name},
    };
  }

  return $tests;
}

1;