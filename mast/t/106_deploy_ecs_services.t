use v5.030;
use strictures 2;
no warnings 'uninitialized';

use File::Slurp;
use Mast::Cloud::Spec;
use Mast::Deploy::Service;

use Test::More;


use lib 't/lib';
use AWS::MockCLIWrapper;

# Need to test value validation test for different envs
my $cloud_spec_json = read_file "t/data/spec/test-baseline-valid-template.json";
my $contexts = ["prestaging", "standby"];
my $cloud_spec_obj = Mast::Cloud::Spec->new(contexts => $contexts, cloud_spec_json => $cloud_spec_json);

my $aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
    mock_aws_state => {
        target_groups => {
            TargetGroups => [
                {'TargetGroupName' => 'tg-placeholder', 'TargetGroupArn' => 'tg-placeholder'}
            ]
        },
        services_data => {
            services => [
                {
                    "taskDefinition" => "arn:aws:ecs:us-west-2:123456789012:task-definition/amazon-ecs-sample:1",
                    "serviceArn" => "arn:aws:ecs:us-west-2:123456789012:service/my-http-service",
                    "runningCount" => 0,
                    "desiredCount" => 0,
                    "events" => [
                        {"message" => "has reached a steady state"}
                    ],
                    "status" => "COMPLETED"
                }
            ]
        }
    }
);

# unsure how to mock specific function calls one-time. seems like advanced functionality. could just create multiple instances of MockCLIWrapper;
my $service = Mast::Deploy::Service->new(
    cloud_spec => $cloud_spec_obj,
    aws => $aws
);

is $service->isa("Mast::Deploy::Service"), 1, "is the expected object";

# count num of services

my @before_services = @{$aws->ecs_list_services};
my @before_active_services = grep { $_->{status} ne "INACTIVE" } @before_services;

is scalar(@before_active_services), 1, "expect 1 service";

$service->create_or_update_ecs_service(task_definition_arn=>"bananas");
my @after_services = @{$aws->ecs_list_services};

my @after_active_services = grep { $_->{status} ne "INACTIVE" } @after_services;
is scalar(@after_active_services), 2, "expect a new service";

# TODO: These test have not been properly written because extensive changes to the MockCLIWrapper will need to be completed
$service->delete_ecs_service;
my @after_delete_services = @{$aws->ecs_list_services};

my @after_delete_active_services = grep { $_->{status} ne "INACTIVE" } @after_delete_services;
is scalar(@after_delete_active_services), 1, "expect back to one new service";


$service->delete_ecs_service;
my @after_after_delete_services = @{$aws->ecs_list_services};
my @after_after_delete_active_services = grep { $_->{status} ne "INACTIVE" } @after_after_delete_services;
is scalar(@after_after_delete_active_services), 1, "expect still 1 service before delete is noop";


done_testing();
