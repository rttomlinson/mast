use v5.030;
use warnings;
no warnings 'uninitialized';

use Test::More;
use Data::Dumper;
use File::Slurp;

use JSON::PP;
use Mast::Service::Spec;

my $tests = eval join '', <DATA>;

for my $test (sort keys %$tests) {
  next if @ARGV and not grep { $_ eq $test } @ARGV;

  my $test_data = $tests->{$test};
  my ($env, $spec_from, $want, $want_from, $is_a, $contexts)
    = @$test_data{qw(environment spec_from want want_from is_a contexts)};

  my $service_spec = read_file $spec_from;
  $want = eval read_file $want_from if not $want and $want_from;

  die "$@" if $@;

  my $spec_obj = eval {
    Mast::Service::Spec->new(environment => $env, service_spec_json => $service_spec, contexts => $contexts);
  };

  is "$@", "", "$test new no exception";
  isa_ok $spec_obj, $is_a // 'Mast::Service::Spec';
  
  if ($want) {
    my $have = $spec_obj->service_spec;

    is_deeply $have, $want, "$test spec";
  }
}

done_testing;

__DATA__
# line 43
{
  'bar-foo-json-staging' => {
    environment => 'staging',
    spec_from => 't/data/spec/bar-foo.json',
    want_from => 't/data/want/bar-foo.pm',
  },
  'bar-baz-json-prestaging' => {
    environment => 'prestaging',
    spec_from => 't/data/spec/bar-baz.json',
    want_from => 't/data/want/bar-baz.pm',
  },
  'bar-baz-json-staging-v1.0' => {
    is_a => 'Mast::Service::Spec::v1_0',
    environment => 'staging',
    spec_from => 't/data/spec/bar-baz-v1_0.json',
    want_from => 't/data/want/bar-baz-v1_0.pm',
  },
  'bar-baz-json-staging-v1.1' => {
    is_a => 'Mast::Service::Spec::v1_1',
    environment => 'staging',
    spec_from => 't/data/spec/bar-baz-v1_1.json',
    want_from => 't/data/want/bar-baz-v1_1.pm',
  },
  'ALBRequestCountbar-baz-json-staging-v1.1' => {
    is_a => 'Mast::Service::Spec::v1_1',
    environment => 'staging',
    spec_from => 't/data/spec/ALBRequestCountPerTarget_bar-baz-v1_1.json',
    want_from => 't/data/want/ALBRequestCountPerTarget_bar-baz-v1_1.pm',
  },
  'ECSServiceAverageCPUUtilizationPolicybar-baz-json-staging-v1.1' => {
    is_a => 'Mast::Service::Spec::v1_1',
    environment => 'staging',
    spec_from => 't/data/spec/ECSServiceAverageCPUUtilizationPolicy_bar-baz-v1_1.json',
    want_from => 't/data/want/ECSServiceAverageCPUUtilizationPolicy_bar-baz-v1_1.pm',
  },
  'bar-baz-json-staging-v1.2' => {
    is_a => 'Mast::Service::Spec::v1_2',
    environment => 'staging',
    spec_from => 't/data/spec/bar-baz-v1_2.json',
    want_from => 't/data/want/bar-baz-v1_2.pm',
  },
  'valid-https-example' => {
    environment => 'staging',
    spec_from => 't/data/spec/elb/https-listener-protocol-elb-ecs.json',
  },
  'valid-http-example' => {
    environment => 'prestaging',
    spec_from => 't/data/spec/elb/http-listener-protocol-elb-ecs.json',
  },
  'valid-nlb-example' => {
    environment => 'prestaging',
    spec_from => 't/data/spec/elb/valid-elb-network-ecs.json',
  },
  'bar-baz-v2_0_multi-alb_staging' => {
    is_a => 'Mast::Service::Spec::v2_0',
    contexts => ['staging', 'active'],
    spec_from => 't/data/spec/bar-baz-v2_0_multi-alb.json',
    want_from => 't/data/want/bar-baz-v2_0_multi-alb.pm',
  },
  'bar-baz-v2_0_diff-albs-multi-tg_staging' => {
    is_a => 'Mast::Service::Spec::v2_0',
    contexts => ['staging', 'active'],
    spec_from => 't/data/spec/bar-baz-v2_0_diff-albs-multi-tg.json',
    want_from => 't/data/want/bar-baz-v2_0_diff-albs-multi-tg.pm',
  },
  'bar-baz-v2_0_diff-nlbs-multi-tg_staging' => {
    is_a => 'Mast::Service::Spec::v2_0',
    contexts => ['staging', 'active'],
    spec_from => 't/data/spec/bar-baz-v2_0_diff-nlbs-multi-tg.json',
    want_from => 't/data/want/bar-baz-v2_0_diff-nlbs-multi-tg.pm',
  },
  'bar-baz-v2_0_multi-alb_staging-foo-port' => {
    is_a => 'Mast::Service::Spec::v2_0',
    contexts => ['staging', 'active', 'foo'],
    spec_from => 't/data/spec/bar-baz-v2_0_multi-alb-foobar-port.json',
    want_from => 't/data/want/bar-baz-v2_0_multi-alb.pm',
  },
  'bar-baz-v2_0_multi-alb_staging-bar-port' => {
    is_a => 'Mast::Service::Spec::v2_0',
    contexts => ['staging', 'active', 'bar'],
    spec_from => 't/data/spec/bar-baz-v2_0_multi-alb-foobar-port.json',
    want_from => 't/data/want/bar-baz-v2_0_multi-alb-port-999.pm',
  },
}
