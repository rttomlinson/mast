package Mast::Cloud::Verification;

use v5.030;
use warnings;
no warnings 'uninitialized';

use Carp 'confess';

sub new {
  my ($class, %params) = @_;

  my $cloud_spec = $params{cloud_spec};

  confess 'Expected Mast::Cloud::Spec object as "cloud_spec" parameter'
      unless $cloud_spec and $cloud_spec->isa('Mast::Cloud::Spec');

  bless { spec => $cloud_spec }, $class;
}

sub verify_service {
  my ($self) = @_;

  my $verification = $self->{spec}->verification;
  my ($request, $want_response) = @$verification{'request', 'response'};

  say "Making a verification request to $request->{url}...";

  my $have_response = _make_request($request);

  say "Received response with HTTP code: $have_response->{status}, checking expectations...";

  # This will terminate if conditions are not met
  _check_response($want_response, $have_response, $request);

  say "Successfully verified service deployment.";
}

my %idempotent_methods = (
  GET => 1,
  HEAD => 1,
);

sub _make_request {
  my ($request) = @_;

  my ($method, $url, $headers, $body) = @$request{qw(method url headers body)};
  $method = uc $method;

  # We're using curl for simplicity. -k implies not verifying TLS certificate,
  # which is going to be the case for almost all if not all verification steps.
  # -s is for suppressing output messages except the response payload itself.
  # -q is for suppressing curlrc, and -i is to include response headers in the
  # output stream.
  my @arg = qw(curl -q -k -s -i);

  # Use single quotes around the header values to prevent shell expansion
  push @arg, ('-H' => qq|'$_'|) for @$headers;

  if ($method && !$idempotent_methods{$method}) {
    push @arg, ('-X', $method);

    push @arg, ('-d', qq|'$body'|) if $body;
  }

  push @arg, $url;

  my $cmd = join " ", @arg;
  my $out = qx{$cmd 2>&1};

  die "$out\n" unless $? == 0;

  # HTTP responses use MS-DOS style \r\n line endings, and an empty line
  # to segregate headers from the body
  my ($resp_headers, $resp_body) = split /\r\n\r\n/, $out;

  # Split headers at newlines and remove newlines
  my @response_headers = map { $_ =~ s/\r?\n$//r } split /\r\n/, $resp_headers;
  my $response_body = $resp_body =~ s/\r?\n$//r;

  # Status line is something like HTTP/1.1 <status_code>
  my $status = (split ' ', shift @response_headers)[-1];

  return {
    status => $status,
    headers => \@response_headers,
    body => $response_body,
  };
}

sub _check_response {
  my ($want, $have, $request) = @_;

  my ($status, $headers, $body) = @$have{qw(status headers body)};

  eval {
    my %acceptable_statuses = map { $_ => 1 } @{$want->{status}};
    
    die "Invalid HTTP response status: $status, expected one of: [" .
      (join ", ", keys %acceptable_statuses) . "]\n"
        unless $acceptable_statuses{$status};
    
    # Header matching is todo

    # If the expected body is enclosed in //, we treat this as a regex to match
    # against the response body. If there are no slashes, this means a literal
    # string to equal with the expectation
    if ($want->{body} =~ m|^/.*/$|) {
      my $pattern = $want->{body} =~ s{^/|/$}{}gr;

      die qq|Response body does not match regular expression: /$pattern/, got: "$have->{body}"\n|
        unless $have->{body} =~ qr{$pattern};
    }
    else {
      # Remove trailing newlines to prevent spurious and hard to detect failures
      # that are essentially meaningless.
      my $w = $want->{body} =~ s/(?:\r?\n)+$//r;
      my $h = $have->{body} =~ s/(?:\r?\n)+$//r;

      die qq|Response body is not matching expectation. Expected: "$w", received: "$h"\n|
        unless $h eq $w;
    }
  };

  if ($@) {
    say STDERR "Request: $request->{method} $request->{url}";
    say STDERR "Request headers:\n" . (join "\n", @{$request->{headers}});
    say STDERR "Request body:\n" . $request->{body};
    say STDERR "Response status: $status";
    say STDERR "Response headers:\n" . (join "\n", @$headers);
    say STDERR "Response body: $body";

    die $@;
  }

  return 1;
}

1;
