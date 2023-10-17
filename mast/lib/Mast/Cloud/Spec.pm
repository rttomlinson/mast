package Mast::Cloud::Spec;

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

  # To make things a bit more readable, we've renamed cloud_spec argument
  # to cloud_spec_json throughout the codebase. Just in case we've forgotten something,
  # error out when we see this argument name.

  my ($spec_text, $contexts) = @arg{qw(cloud_spec_json contexts)};

  my $parsed_spec = eval { decode_json $spec_text };

  confess "Cannot parse cloud_spec: $@"
    if $@ and not $parsed_spec;

  my $version = delete $parsed_spec->{version};
  
  $contexts //= [];
  confess "Cannot parse cloud_spec: $@"
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
  my ($contexts, $cloud_spec) = @_;

  my $collapsed_spec = $cloud_spec;

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