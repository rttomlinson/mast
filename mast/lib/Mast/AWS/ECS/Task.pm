package Mast::AWS::ECS::Task;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Carp 'confess';
use JSON::PP;
use POSIX ":sys_wait_h";
use AWS::CLIWrapper;

use Mast::AWS::ECS::TaskDefinition;

my @required = qw(desired_count launch_type network_configuration);

sub new {
  my ($class, %params) = @_;

  confess "ECS cluster name or ARN is required"
    unless defined $params{cluster};
  
  confess "TaskDefinition object or ECS task definition ARN is required"
    if 'Mast::AWS::ECS::TaskDefinition' ne ref($params{task_definition})
      and not defined $params{task_definition_arn};
  
  for my $prop (@required) {
    confess "$prop is required" unless defined $params{$prop};
  }
  
  my $aws_region = $params{aws_region};
  my $poll_interval = delete $params{poll_interval} // 10;

  my $aws = delete $params{aws};
  $aws //= AWS::CLIWrapper->new(
      region => $aws_region,
      croak_on_error => 1,
  );

  if (not $params{task_definition}) {
    $params{task_definition} = Mast::AWS::ECS::TaskDefinition->new(
      aws_region => $aws_region,
      arn => $params{task_definition_arn},
      aws => $aws,
    );
  }

  bless { aws => $aws, poll_interval => $poll_interval, %params, _tasks => [] }, $class;
}

sub aws_task_def {
  my ($self) = @_;

  return $self->{_task_def} if $self->{_task_def};

  $self->{_task_def} = $self->{task_definition}->describe;
}

sub describe {
  my ($self) = @_;

  return () unless @{$self->{_tasks}};

  my $res = $self->{aws}->ecs('describe-tasks', {
    cluster => $self->{cluster},
    tasks => join " ", map { $_->{taskArn}} @{$self->{_tasks}},
  });

  return map { $_->{taskId} = _aws_task_id($_); $_ } @{$res->{tasks}};
}

sub execute {
  my ($self, $printer, %params) = @_;

  my $cluster = $self->{cluster};
  my $task_def_arn = $self->aws_task_def->{taskDefinitionArn};
  my $desired_count = $self->{desired_count};
  my $overrides = $params{overrides};

  confess "Desired count of ECS tasks more than 1 is not supported at this time, input: $desired_count"
    if $desired_count > 1;
  
  $printer->("Starting $desired_count ECS task(s) for task definition $task_def_arn in cluster $cluster...");
  
  my @aws_tasks;

  TRY_START: {
    @aws_tasks = do {
      my $res = $self->{aws}->ecs('run-task', {
        cluster => $cluster,
        count => $desired_count,
        'launch-type' => $self->{launch_type},
        'task-definition' => $task_def_arn,
        'network-configuration' => encode_json $self->{network_configuration},
        $overrides ? (overrides => encode_json $overrides) : (),
      });

      @{$res->{tasks}};
    };

    if (not @aws_tasks) {
      $printer->("ECS run-task returned empty list of started tasks, retrying...");
      redo TRY_START;
    }

    $self->{_tasks} = \@aws_tasks;

    if (not $self->wait_for_tasks($printer, 'RUNNING', 'STOPPED')) {
      $printer->("ECS task(s) failed to start, retrying...");
      redo TRY_START;
    }
  }

  $printer->("Successfully started " . (scalar @aws_tasks) . " task in cluster $cluster");

  return @aws_tasks;
}

sub wait_for_tasks {
  my ($self, $printer, $want_status, $do_not_want_status) = @_;

  my $poll_interval = $self->{poll_interval};
  $want_status = uc $want_status;
  $do_not_want_status = uc $do_not_want_status;

  $printer->("Waiting for ECS task(s) to reach $want_status status...");

  my @aws_tasks;

  while (1) {
    @aws_tasks = $self->describe;

    my $reached_status = 0;

    for my $task (@aws_tasks) {
      $printer->("Task id $task->{taskId} is in status: $task->{lastStatus}");

      # This is a bit kludgy for a circuit breaker, however we're limiting the number
      # of simultaneously started ECS tasks to 1 so it's sorta ok.
      # TODO/AT Revisit this.
      return if $task->{lastStatus} eq $do_not_want_status;

      $reached_status++ if $task->{lastStatus} eq $want_status;
    }

    last if $reached_status == @aws_tasks;

    $printer->("$reached_status of " . (scalar @aws_tasks) . " task(s) has reached $want_status status, waiting $poll_interval seconds...");

    sleep $poll_interval;
  }

  return @aws_tasks;
}

sub watch_logs {
  my ($self, $printer) = @_;

  my @aws_tasks = $self->describe;

  if (not @aws_tasks) {
    $printer->("No ECS tasks are found to watch logs for");

    return;
  }

  $printer->("Resolving log configuration for " . (scalar @aws_tasks) . " ECS task(s)...");

  my (@log_streams, @task_arns);
  my $idx = 1;

  for my $task (@aws_tasks) {
    push @task_arns, $task->{taskArn};
    my $task_id = _aws_task_id($task);
    my $task_def = $self->aws_task_def;

    for my $container (@{$task_def->{containerDefinitions}}) {
      my $container_name = $container->{name};
      my $log_options = $container->{logConfiguration}->{options};

      push @log_streams, {
        prefix => "task $idx $container_name",
        group => $log_options->{'awslogs-group'},
        stream => $log_options->{'awslogs-stream-prefix'} . "/$container_name/$task_id",
      };
    }
  }

  $printer->("Watching log streams for " . (scalar @aws_tasks) . " ECS task(s):\n");
  $printer->("---- START OF TASK LOG STREAM ----");

  if (@log_streams == 1) {
    $log_streams[0]->{prefix} = '';
  }

  my @log_watcher_pids;

  for my $log (@log_streams) {
    my $pid = fork;
    
    die "Cannot fork: $!" unless defined $pid;
    
    if (not $pid) {
      my ($next_token, $final_countdown);
      
      # The parent process will send SIGTERM when the ECS task exits.
      # We want to give this process a chance to catch up with the latest
      # log entries when that happens.
      $SIG{TERM} = sub { $final_countdown = 1 };
      
      while (not defined $final_countdown or $final_countdown >= 0) {
        sleep $self->{poll_interval};
        
        my $res;
        
        eval {
          $res = $self->{aws}->logs('get-log-events', {
            'log-group-name' => $log->{group},
            'log-stream-name' => $log->{stream},
            'start-from-head' => '',
            $next_token ? ('next-token' => $next_token) : (),
          });
        };
    
        # If we started polling for log events before the task had a chance
        # to start, get-log-events will error out. 
        die "$@" if $@ && $@ !~ /ResourceNotFoundException/;
        
        $next_token = $res->{nextForwardToken};

        $printer->($log->{prefix} . $_->{message}) for @{$res->{events}};
        
        $final_countdown-- if defined $final_countdown;
      }
      
      # We're in a child process here, need to exit cleanly.
      exit 0;
    }
    
    push @log_watcher_pids, $pid;
  }

  # Now we just wait until all ECS tasks finish. Note that we're not setting
  # a timer to prevent endlessly running tasks; this code is intended to be
  # executed as a pipeline step in a CI/CD environment that implements its own
  # timeout mechanism.
  $self->wait_for_tasks(sub {}, 'STOPPED');

  $printer->("---- END OF TASK LOG STREAM ----\n");

  $printer->("Terminating log watching processes: " . (join ", ", @log_watcher_pids));
  kill 'TERM', @log_watcher_pids;

  # This is to prevent "zombie" child processes
  {
      my $child_pid;

      do {
          $child_pid = waitpid -1, WNOHANG;
      } while $child_pid > 0;
  }
}

sub print_container_exit_codes {
  my ($self, $printer) = @_;

  my @aws_tasks = $self->describe;

  for my $task (@aws_tasks) {
    for my $container (@{$task->{containers}}) {
      my $task_id = _aws_task_id($container);
      $printer->("Container $container->{name} in task id $task_id exited with code $container->{exitCode}");
    }
  }
}

sub get_container_with_highest_exit_code {
  my ($self) = @_;

  my @aws_tasks = $self->describe;

  # Determinining exit code for a task set with potentially more than one
  # container per each task is not trivial semantically, so we default to
  # grabbing the highest code from a container marked as essential, and then
  # taking the highest exit code from the task set.
  my @worst_containers = sort { $a->{exitCode} <=> $b->{exitCode} }
                          map { $self->get_container_with_worst_exit_code_for_task($_) }
                              @aws_tasks;

  return pop @worst_containers;
}

sub get_container_with_worst_exit_code_for_task {
  my ($self, $aws_task) = @_;

  my $task_def = $self->aws_task_def;

  my %essential_containers = map { $_->{name} => 1 }
                            grep { $_->{essential} }
                                @{$task_def->{containerDefinitions}};

  my @exit_codes = map { $_->{taskId} = $aws_task->{taskId}; $_ }
                  sort { $a->{exitCode} <=> $b->{exitCode} }
                  grep { $essential_containers{$_->{name}} }
                      @{$aws_task->{containers}};

  return pop @exit_codes;
}

sub _aws_task_id { (split qr|/|, shift->{taskArn})[-1] }

1;
