use v5.030;
use warnings;

use File::Slurp;
use JSON::PP;
use Carp 'confess';
use Mast::Service::Spec;
use Test::More;
use Test::Exception;
# use Test::LectroTest;
use Digest::SHA qw(sha1_hex);
use Storable 'dclone';

# Recursive build spec from top level levels?

plan skip_all => 'never run these test. just for playing around and wip';
exit 0;

# reverse normalization WIP

# Recursive build spec from top level levels?
my @environments = ('prestaging', 'staging', 'production');
sub reverse_normalize_value {
  my ($value) = @_;

  # if value is scalar, then we've reached the end
  if (not ref $value or JSON::PP::is_bool($value)) {
    my %new_values = ();
    for(@environments){
        $new_values{$_} = dclone($value);
    }
    return \%new_values;
  }
  my $should_replace = Frequency( [20, Unit(1)],
                                  [80, Unit(0)], ); # weighted to favor deeper nesting

  if($should_replace->generate){
    # for each in environments, make a hash with key environment and value of value
    my %new_values = ();
    for(@environments){
        $new_values{$_} = dclone($value);
    }
    return \%new_values;
  } else {
    if ('ARRAY' eq ref $value) {
        for(0..$#{$value}){
            $value->[$_] = reverse_normalize_value($value->[$_]);
        }
    } elsif ('HASH' eq ref $value) {
        foreach my $key (sort(keys %{$value})) {
            $value->{$key} = reverse_normalize_value($value->{$key});
        }
    } else {
        my $ref_value = ref $value;
        confess "Something went wrong!!! Ref value unknown: $ref_value";
    }
    return $value;
  }
}

# my $environment_gen = Elements('prestaging', 'staging', 'production');
# # Generate invalid service specs and see if any pass

# my $service_spec_json_gen = Gen {
#     my $service_spec_from = eval read_file 't/data/want/service-spec-template.pm';

#     # always skip the top level
#     foreach my $key (sort(keys %{$service_spec_from})) {
#         $service_spec_from->{$key} = reverse_normalize_value($service_spec_from->{$key});
#     }
    
#     my $service_spec_json = encode_json($service_spec_from);
#     return $service_spec_json;
# };

# randomly drop an env value

# use Data::Dumper;
# my $service_spec_from = eval read_file 't/data/want/service-spec-template.pm';
# # always skip the top level
# foreach my $key (sort(keys %{$service_spec_from})) {
#     $service_spec_from->{$key} = reverse_normalize_value($service_spec_from->{$key});
# }
# # say Dumper($service_spec_from);
# say Dumper(encode_json($service_spec_from));

# Property {
#     ##[ environment <- $environment_gen, service_spec_json <- $service_spec_json_gen ]##
#     my $res = eval {Mast::Service::Spec->new(environment => $environment, service_spec_json => $service_spec_json,)};
#     1;
# }, name => "when a user attempts to use a Spec, it must have an a value for the environment provided" ;

for my $environment (@environments){
#   my $test_data = $tests->{$test};
#   my ($env, $spec_from, $want, $want_from) = @$test_data{qw(environment spec_from want want_from)};
  my $spec_from = "t/data/spec/test-missing-$environment-environment-values-tree.json";
  my $service_spec = read_file $spec_from;
#   $want = eval read_file $want_from if not $want and $want_from;

#   my $spec_obj = eval {
#     Mast::Service::Spec->new(environment => $env, service_spec_json => $service_spec);
#   };
  # Check that the stringified exception matches given regex
  throws_ok { Mast::Service::Spec->new(environment => $environment, service_spec_json => $service_spec); } qr/value for $environment not found but was expected. you likely forgot to add it in your spec. this will likely result in an error during deployment./, 'missing value for environment';
#   is "$@", "", "$test new no exception";
#   isa_ok $spec_obj, 'Mast::Service::Spec';
  
#   my $have = $spec_obj->service_spec;

#   is_deeply $have, $want, "$test spec";
}

# done_testing;
