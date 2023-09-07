use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Test::More;
use Test::Exception;

use Data::Dumper;
use File::Slurp;

use JSON::PP;

use Mast::Service::Spec;
use Mast::Deploy::TaskDefinition;

use lib 't/lib';
use AWS::MockCLIWrapper;

# Need to test value validation test for different envs
my $service_spec_json = read_file "t/data/spec/test-baseline-valid-template.json";
my $env = "prestaging";
my $service_spec_obj = Mast::Service::Spec->new(environment => $env, service_spec_json => $service_spec_json);
my $aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
);
# unsure how to mock specific function calls one-time. seems like advanced functionality. could just create multiple instances of MockCLIWrapper;
my $td = Mast::Deploy::TaskDefinition->new(
    service_spec => $service_spec_obj,
    aws => $aws
);

is $td->isa("Mast::Deploy::TaskDefinition"), 1, "is the expected object";

$td->create_task_definition(service_spec_url => "docker://hololol");
$td->delete_task_definition(
    task_definition_arn => "hello"
);


done_testing();
