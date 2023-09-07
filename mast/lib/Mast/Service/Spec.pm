package Mast::Service::Spec;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Exporter 'import';
use Carp 'croak', 'confess';
use Scalar::Util 'looks_like_number', 'dualvar';
use JSON::PP;

our @EXPORT_OK = qw(collapser);

sub new {
  my ($class, %arg) = @_;

  # To make things a bit more readable, we've renamed service_spec argument
  # to service_spec_json throughout the codebase. Just in case we've forgotten something,
  # error out when we see this argument name.

  confess "service_spec argument name is deprecated, use service_spec_json"
    if exists $arg{service_spec};

  my ($environment, $spec_text, $contexts) = @arg{qw(environment service_spec_json contexts)};

  my $parsed_spec = eval { decode_json $spec_text };

  confess "Cannot parse service_spec: $@"
    if $@ and not $parsed_spec;

  my $version = delete $parsed_spec->{version};

  # discard contexts if version is less than 2.x
  if (defined $contexts and scalar(@$contexts) and $version < 2) {
    confess "contexts is not supported in versions less than 2.x. Either upgrade your version or rewrite your spec to not require contexts.";
  }
  
  # contexts allows for multiple passes and is meant to replace $environment. $environment is kept for backwards compatability
  if (defined $environment) {
    # warn "environment is deprecated. use context options";
    if (defined $contexts) {
      # warn "context(s) and environments should not both be defined, but we will process using both starting with environment. You probably just want to use context(s).\n";
      unshift(@$contexts, $environment);
    } else {
      $contexts = [$environment,];
    }
  } else {
    $contexts = [] unless defined $contexts;
  }
  
  confess "Cannot parse service_spec: $@"
    if $@ and not $parsed_spec;


  if (not defined $version) {
    warn "No version property found in the spec document, assuming prehistoric v0\n";
    $version = '0';
  }

  my $package = (__PACKAGE__ . "::v$version") =~ s/\./_/gr;

  eval "require $package"
    or croak "Cannot load parser for service spec version $version: $@";

  my $collapsed_spec = collapser($contexts, $parsed_spec);

  {
    no strict 'refs';

    my $version = *{"${package}::VERSION"}{ARRAY};

    if ($version) {
      $collapsed_spec->{version} = dualvar $version->[0], $version->[1];
    }
  }

  my $self = bless { spec => $collapsed_spec }, $package;

  $self->_normalize_spec();

  return $self;
}

sub collapser {
  my ($contexts, $service_spec) = @_;

  my $collapsed_spec = $service_spec;

  for my $context (@$contexts) {
    $collapsed_spec = collapse_value($context, $collapsed_spec);
  }
  return $collapsed_spec;
}

# we look for the env as a key in hashes and will replace the entire hash value with the value of the env key
sub collapse_value {
  my ($context, $value) = @_;

  if (not ref $value) {
    return looks_like_number($value) ? $value + 0 : $value;
  }

  return $value if JSON::PP::is_bool($value);

  if ('ARRAY' eq ref $value) {
    return [map { collapse_value($context, $_) } @$value];
  }

  if ('HASH' eq ref $value) {
    if(exists $value->{$context}) {
      my $actual = $value->{$context};
      return collapse_value($context, $actual);
    }
    return { map { $_ => collapse_value($context, $value->{$_}) } keys %$value };
  }

  confess "Something unexpected happened?";
}

sub bool_str {
  my ($value) = @_;

  return $value ? 'true' : 'false';
}

sub stringify {
  my ($self, $value) = @_;

  return JSON::PP::is_bool($value) ? bool_str($value) : "$value";
}

sub _get_value {
  my ($self, $format, $value) = @_;

  return (lc $format eq 'json') ? encode_json($value) : $value;
}

1;