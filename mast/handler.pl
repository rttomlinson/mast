#!/usr/bin/env perl
use v5.030;
use strictures 2;
use warnings;
no warnings 'uninitialized';

$| = 1;
use Carp;
use JSON::PP;

sub handle {
    my ($payload, $context) = @_;
    
    my $step_name = $payload->{step_name};
    my @mast_args = keys %{$payload};

    ####
    ## LOGGING CONFIG END
    ####
    my $aws_request_id = $context->aws_request_id;

    # This is relevant to perl command because it looks for this value. This feels really bad, but maybe there's a way to make it better?
    # Some kind of interface for the logging or something
    $ENV{AWS_LAMBDA_REQUEST_ID} = $aws_request_id if defined $aws_request_id;
    use Mast::CustomLogger qw(lambda_say lambda_confess lambda_die);
    # The identifier of the invocation request.
    ####
    ## LOGGING CONFIG START
    ####
    # my $printer = sub { lambda_say "mast-lambda (handler.handle), RequestId: $aws_request_id, ", join "", @_ };
    # lambda_say "trying to get trace id";
    # lambda_say $ENV{_X_AMZN_TRACE_ID};
    # my $aws_lambda_runtime_api = $ENV{AWS_LAMBDA_RUNTIME_API};
    # my $contents = get("http://${aws_lambda_runtime_api}/2018-06-01/runtime/invocation/next");
    # say Dumper($contents);
    # my $output_key = $payload->{output_key};
    # if (not defined $output_key) {
    #     # Result scope is used to name the output values without overriding existing global state
    #     my @set = ('0' ..'9', 'A' .. 'F');
    #     $output_key = join '' => map $set[rand @set], 1 .. 8;
    # }
    # @mast_args = grep(!/output_key/, @mast_args); # need to hardcode this
    
    @mast_args = grep(!/step_name/, @mast_args); # need to hardcode this

    lambda_confess "step_name not provided. exiting" unless defined $step_name;
    my $script_location = "/opt/bin/$step_name"; # don't know how to not hardcode this

    my @p_args = ($script_location,);
    for(@mast_args) {
        my $next_val = $payload->{$_};
        my $hyphens_arg = $_;
        $hyphens_arg=~s/_/-/g;
        $hyphens_arg = "--${hyphens_arg}";
        # if a val is an array, then split the array into individual arguments
        if (ref $next_val eq 'ARRAY'){
            for my $val (@{$next_val}) {
                my @arg_pair = ($hyphens_arg, $val);
                push(@p_args, @arg_pair);
            }
        } else {
            my @arg_pair = ($hyphens_arg, $next_val);
            push(@p_args, @arg_pair);
        }
    }
    
    # my $trace_id = $context->{'trace_id'};

    system("perl", @p_args) == 0
        or lambda_die "system perl @p_args failed: $?";
    # system("perl", "/opt/bin/$step_name", "--environment", "$environment", "--cloud-spec-json" $cloud_spec_json,); 
    # my $files = `perl /opt/bin/validate_cloud_spec --environment $val --cloud-spec-json "{}"`;
    # say $files;

    return unless defined $payload->{output_file};
    # if output file exists, read from output file and populate the return payload
    my %result_output;
    my $file = $payload->{output_file};
    open my $info, $file or lambda_die "Could not open $file: $!";
    # my $decoded_json = decode_json($global_state);
    while( my $line = <$info>)  {
        chomp $line; 
        my @spl = split("=", $line);
        my $key = $spl[0];
        my $value = $spl[1];
        $result_output{$key} = $value;

    }
    close $info;
    return \%result_output;
}

1;
