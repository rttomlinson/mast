use v5.030;
use warnings;
no warnings 'uninitialized';

use Test::More;
use Test::Exception;

use Data::Dumper;
use File::Slurp;

use JSON::PP;

use Mast::Cloud::Spec;
use Mast::Deploy::Service;

use lib 't/lib';
use AWS::MockCLIWrapper;

# Need to test value validation test for different envs
my $cloud_spec_json = read_file "t/data/spec/test-baseline-valid-template.json";
my $contexts = ["prestaging", "active"];
my $cloud_spec_obj = Mast::Cloud::Spec->new(contexts => $contexts, cloud_spec_json => $cloud_spec_json);

my $aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
    service_actors_override => {
        elbv2 => {
            'describe-target-groups' => sub {
                my ($self, $args, %additional_params) = @_;
                return {
                    TargetGroups => [{
                    TargetGroupArn => "yooooo",
                    TargetGroupName => $args->{name},
                    }]
                };
            }
        }
    }
);

{
    # unsure how to mock specific function calls one-time. seems like advanced functionality. could just create multiple instances of MockCLIWrapper;
    my $service = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec_obj,
        aws => $aws,
        poll_interval => 0,
    );

    is $service->isa("Mast::Deploy::Service"), 1, "is the expected object";

    # test behavior of calling different functions
    my $service_obj = $service->get_service_object;
    my $create_service = $service->create_or_update_ecs_service(
        task_definition_arn => "hello"
    );

    $service->get_current_task_count;
    $service->scale_task_count;
    $service->delete_ecs_service;
    $service->register_service_as_scalable_target_and_attach_scaling_policy;
    $service->deregister_service_as_scalable_target_and_delete_scaling_policy;
    $service->update_current_active_service_tag_on_cluster;
}

{
    # unsure how to mock specific function calls one-time. seems like advanced functionality. could just create multiple instances of MockCLIWrapper;
    my $service = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec_obj,
        aws => $aws,
        poll_interval => 0,
    );

    $service->create_or_update_ecs_service(
        task_definition_arn => "foo"
    );

    $service->update_ecs_service(
        task_definition_arn => "bar"
    );
}

done_testing();
