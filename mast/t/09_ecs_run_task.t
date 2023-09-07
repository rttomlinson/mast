use v5.030;
use warnings;
no warnings 'uninitialized';

use Test::More;
use File::Slurp;

use Mast::Service::Spec;
use Mast::Deploy::Service;
use Mast::AWS::ECS::Task;

use lib 't/lib';
use AWS::MockCLIWrapper;

my %next_status = (
  PROVISIONING => 'PENDING',
  PENDING => 'RUNNING',
  RUNNING => 'DEACTIVATING',
  DEACTIVATING => 'STOPPED',
);

our $start_retries = 0;

my $service_spec_json = read_file "t/data/spec/bar-baz-v1_1.json";
my $env = "staging";
my $service_spec_obj = Mast::Service::Spec->new(
  environment => $env,
  service_spec_json => $service_spec_json,
);

my $task_spec = $service_spec_obj->ecs->{tasks}->{standbySmokeTest};
my $task_def = $task_spec->{taskDefinition};
my $network_configuration = $task_spec->{networkConfiguration};
my $task_def_arn = "arn:foo:bar:taskdefinition:1234";

my $run_task_count = 0;

my $aws = AWS::MockCLIWrapper->new(
  aws_region => 'us-east-1',
  actors => {
    ecs => {
      'describe-task-definition' => sub {
        return {
          taskDefinition => {
            taskDefinitionArn => $task_def_arn,
            %$task_def,
          },
        };
      },
      'run-task' => sub {
        my ($self, $params) = @_;

        if (not $run_task_count++) {
          is $params->{cluster}, "frontend-staging", "task cluster";
          is $params->{count}, 1, "task desired count";
          is $params->{'launch-type'}, "FARGATE", "task launch type";
          is $params->{'task-definition'}, $task_def_arn, "task definition arn";
        }

        my $task_arn = 'arn:task:foobar/1234';

        $self->{_ecs_tasks} //= {};
        my $task = $self->{_ecs_tasks}->{$task_arn} = {
          taskArn => $task_arn,
          lastStatus => 'PENDING',
        };

        return { tasks => [{ %$task }] };
      },
      'describe-tasks' => sub {
        my ($self, $params) = @_;

        my @task_arns = split / /, $params->{tasks};
        my @tasks;

        for my $task_arn (@task_arns) {
          my $task = $self->{_ecs_tasks}->{$task_arn};

          die "No task mock found for arn $task_arn" unless $task;

          $task->{lastStatus} = $next_status{$task->{lastStatus}};

          if ($task->{lastStatus} eq 'RUNNING' and --$start_retries > 0) {
            $task->{lastStatus} = 'STOPPED';
          }

          push @tasks, $task;
        }

        return { tasks => \@tasks };
      },
    },
  },
);

my $task_runner = Mast::AWS::ECS::Task->new(
  aws => $aws,
  aws_region => 'us-east-1',
  cluster => 'frontend-staging',
  task_definition_arn => $task_def_arn,
  desired_count => 1,
  launch_type => 'FARGATE',
  network_configuration => $network_configuration,
  poll_interval => 0,
);

{
  my @tasks = $task_runner->execute(sub { diag @_ });

  is scalar @tasks, 1, "started task count";
}

{
  local $start_retries = 3;

  my @tasks = $task_runner->execute(sub { diag @_ });

  is $start_retries, 0, "start retries";
  is scalar @tasks, 1, "started task count";
}

done_testing;