use v5.030;
use warnings;
use JSON::PP;
use Mast::AWS::ECS::Service;
use Mast::AWS::ECS::Task;
# use Mast::Deploy::Step;

use lib 't/lib';
use AWS::MockCLIWrapper;


# my ($environment, $cloud_spec_json, $docker_username, $docker_password, $github_token) = ('dev', '{}', 'a', 'p', 'z');
# get_cloud_spec_from_active_service_cluster_tag(
#     environment => $environment, 
#     cloud_spec_json => $cloud_spec_json, 
#     docker_username => $docker_username, 
#     docker_password => $docker_password, 
#     github_token => $github_token,
#     aws => $aws
# );
use Test::More;
plan skip_all => 'skip me for now' unless $ENV{mock_tests};
exit 0;
# $aws->ecs;
my $aws;
my $service;
$aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
);

$service = Mast::AWS::ECS::Service->new(
    cluster => "bahamas",
    name => "secret_service",
    aws_region => "us-east-8",
    aws => $aws,
);

use Data::Dumper;
say Dumper($service->describe);


# expect create success if service not found
$aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
);
$service = Mast::AWS::ECS::Service->new(
    cluster => "bahamas",
    name => "secret_service",
    aws_region => "us-east-8",
    aws => $aws,
);
say Dumper($service->create(
    sub { say @_ }, # printer

    task_definition_arn => "hello-world"
));

say Dumper($service->update(
    sub { say @_ },
    'forceNewDeployment' => "",
    'task_definition_arn' => "some junk",
));
say Dumper($service->remove);
say Dumper($service->wait_running_count);
say Dumper($service->wait_steady_state);


say Dumper($service->list_tasks(sub {}));
say Dumper($service->stop_tasks(
    sub { say @_ },
    ["hey"],
));
say Dumper($service->describe_cluster(
    sub { say @_ },
    ["hey"],
));
say Dumper($service->describe_cluster(
    cluster_name => "hello",
));
say Dumper($service->tag_resource(
    "hello",
    encode_json([
        'key' => 'ey',
        'value' => 'there'
        ]),
));
say Dumper($service->update_ecs_service);
say Dumper($service->restart_tasks);
# say Dumper($service->trigger_rolling_deploy);


use Mast::AWS::ECS::TaskDefinition;
my $td = Mast::AWS::ECS::TaskDefinition->new(
    family => "heythere",
    containerDefinitions => [
    ],
    executionRoleArn => "abc",
    taskRoleArn => "123",
    requiresCompatibilities => ["FARGATE"],
    memory => 1,
    cpu => 1,
    networkMode => "awsvpc",
    aws => $aws,
);

say Dumper($td->describe);
my $task_definition_arn = $td->create;
say Dumper($task_definition_arn);
say Dumper($td->remove);


# task_definition => {};
my $t = Mast::AWS::ECS::Task->new(
    cluster => "general_cluster",
    task_definition_arn => "yooo",
    desired_count => 1,
    launch_type => ["FARGATE"],
    network_configuration => {},
    aws => $aws
);
say Dumper($t->describe);
say Dumper($t->execute(
    sub { say @_ }
));

say Dumper($t->watch_logs(
    sub { say @_ }
));
say Dumper($t->wait_for_tasks(
    sub { say @_ }
));
say Dumper($t->print_container_exit_codes(
    sub { say @_ }
));
say Dumper($t->get_container_with_highest_exit_code(
    sub { say @_ }
));
say Dumper($t->get_container_with_worst_exit_code_for_task(
    {
        containers => []
    }
));

use Mast::AWS::ELB::LoadBalancer;
my $elb = Mast::AWS::ELB::LoadBalancer->new(
    listener => {
        protocol => "SSS",
        port => 123
    },
    aws => $aws
);


use Mast::AWS::ELB::TargetGroup;
my $tg = Mast::AWS::ELB::TargetGroup->new(
    name => "mytg",
    protocol => "SSS",
    port => 555,
    aws => $aws
);

say Dumper($tg->create);
say Dumper($tg->remove);


say Dumper($elb->describe);
my $elb_listener_rule = $elb->create_rule(
    {placement => "end", conditions => []},
    $tg,
);

say Dumper($elb->update_rule(
    $elb_listener_rule,
    $tg,
));

say Dumper($elb->delete_rule(
    $elb_listener_rule,
));

use Mast::AWS::ApplicationAutoscaling::ScalableTarget;
use Mast::AWS::ApplicationAutoscaling::ScalingPolicy;

my $aast = Mast::AWS::ApplicationAutoscaling::ScalableTarget->new(
    aws_region => 'us-east-8',
    resource_id => '',
    aws => $aws
);

$aast->describe;
$aast->create;
$aast->remove;

my $aasp = Mast::AWS::ApplicationAutoscaling::ScalingPolicy->new(
    aws_region => 'us-east-8',
    policy_name => '',
    aws => $aws
);

$aasp->describe;
$aasp->create;
$aasp->remove;

