use v5.030;
use warnings;
no warnings 'uninitialized';

use Test::More;
use Test::Exception;

use Data::Dumper;
use File::Slurp;

use JSON::PP;

use Mast::Service::Spec;
use Mast::Service::Metadata;

use lib 't/lib';
use AWS::MockCLIWrapper;

# Need to test value validation test for different envs
my $service_spec_json = read_file "t/data/spec/test-baseline-valid-template.json";
my $env = "prestaging";
my $service_spec_obj = Mast::Service::Spec->new(environment => $env, service_spec_json => $service_spec_json);

# override describe-target-groups to just pretend that one already exists

my $aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
    service_actors_override => {
        ecs => {
            'describe-services' => sub {
                my ($self, $args, %additional_params) = @_;
                return {
                    "services" => 
                    [
                        {
                        "taskDefinition" => "arn:aws:ecs:us-west-2:123456789012:task-definition/amazon-ecs-sample:1",
                        "serviceArn" => "arn:aws:ecs:us-west-2:123456789012:service/my-http-service",
                        "runningCount" => 0,
                        "desiredCount" => 0,
                        "events" => [
                            {"message" => "has reached a steady state"}
                        ],
                        "status" => "HELLO"
                        }
                    ]
                };
            }
        }
    }
);
# unsure how to mock specific function calls one-time. seems like advanced functionality. could just create multiple instances of MockCLIWrapper;
my $m = Mast::Service::Metadata->new(
    aws => $aws,
);

is $m->isa("Mast::Service::Metadata"), 1, "is the expected object";

$m->check_if_tag_exists_on_cluster;
$m->get_ecs_service_name_from_active_service_cluster_tag("me_cluster", "me_family");
$m->get_task_definition_arn_from_ecs_service(
    cluster => "me_cluster_arn"
);
$m->get_spec_url_from_task_definition_tags;

done_testing();
