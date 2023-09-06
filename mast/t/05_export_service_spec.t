use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Test::More;
use File::Slurp;

use JSON::PP;
use Mast::Service::Spec;
use Mast::Deploy::Step;

my $tests = eval join '', <DATA>;

for my $test (sort keys %$tests) {
  next if @ARGV and not grep { $_ eq $test } @ARGV;

  my $test_data = $tests->{$test};
  my ($env, $spec_from, $want_from, $contexts)
    = @$test_data{qw(environment spec_from want_from contexts)};

  my $service_spec = read_file $spec_from;
  my $want = eval read_file $want_from;

  die "$@" if $@;

  my $have = eval {
    Mast::Deploy::Step::validate_service_spec(
      environment => $env,
      service_spec_json => $service_spec,
      contexts => $contexts,
    )->service_spec
  };

  is "$@", "", "$test new no exception";

  is_deeply $have, $want, "$test spec";
}

done_testing;

__DATA__
# line 42
{
  'bar-baz-1.2-to-2.0-staging' => {
    environment => 'staging',
    spec_from => 't/data/spec/bar-baz-v1_2.json',
    want_from => 't/data/want/bar-baz-out.pm',
  },
}
