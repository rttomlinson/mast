use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Test::More;
use File::Slurp;

use JSON::PP;
use Mast::Cloud::Spec;
use Mast::Deploy::Step;

my $tests = eval join '', <DATA>;

for my $test (sort keys %$tests) {
  next if @ARGV and not grep { $_ eq $test } @ARGV;

  my $test_data = $tests->{$test};
  my ($spec_from, $want_from, $contexts)
    = @$test_data{qw(spec_from want_from contexts)};

  my $cloud_spec = read_file $spec_from;
  my $want = eval read_file $want_from;

  die "$@" if $@;

  my $have = eval {
    Mast::Deploy::Step::validate_cloud_spec(
      cloud_spec_json => $cloud_spec,
      contexts => $contexts,
    )->cloud_spec
  };

  is "$@", "", "$test new no exception";

  is_deeply $have, $want, "$test spec";
}

done_testing;

__DATA__
# line 42
{
  'bar-baz-1.0-staging' => {
    contexts => ['staging', 'standby'],
    spec_from => 't/data/spec/bar-baz-v1_0.json',
    want_from => 't/data/want/bar-baz-out.pm',
  },
}
