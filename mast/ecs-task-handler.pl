#!/usr/bin/env perl
use v5.030;
use strictures 2;
use warnings;
no warnings 'uninitialized';

use Carp;
use JSON::PP;

sub handle {
    my ($payload, $context) = @_;
    my $step_name = $payload->{step_name};
    my @mast_args = keys %{$payload};
    
    @mast_args = grep(!/step_name/, @mast_args); # need to hardcode this

    my $global_state = $payload->{global_state};
    @mast_args = grep(!/global_state/, @mast_args) if defined $global_state; # need to hardcode this
    
    confess "step_name not provided. exiting" unless defined $step_name;
    my $script_location = "/opt/bin/$step_name"; # don't know how to not hardcode this

    my @p_args = ($script_location,);
    for(@mast_args) {
        my $hyphens_arg = $_;
        $hyphens_arg=~s/_/-/g;
        $hyphens_arg = "--${hyphens_arg}";
        my @arg_pair = ($hyphens_arg, $payload->{$_});
        push(@p_args, @arg_pair);
    }

    say @p_args;
    # system("perl", @p_args) == 0
    #     or die "system perl @p_args failed: $?";
    # system("perl", "/opt/bin/$step_name", "--environment", "$environment", "--service-spec-json" $service_spec_json,); 
    # my $files = `perl /opt/bin/validate_service_spec --environment $val --service-spec-json "{}"`;
    # say $files;
    # if output file exists, read from output file and populate the return payload
    if (defined $payload->{output_file}) {
        my $file = $payload->{output_file};
        open my $info, $file or die "Could not open $file: $!";
        # my $decoded_json = decode_json($global_state);
        while( my $line = <$info>)  {
            chomp $line; 
            my @spl = split("=", $line);
            my $key = $spl[0];
            my $value = $spl[1];
            $global_state->{$key} = $value;
            # $decoded_json->{$key} = $value;

        }
        # $payload->{global_state} = encode_json($decoded_json);
        $payload->{global_state} = $global_state;
        close $info;
    }
    return $payload;
}
1;