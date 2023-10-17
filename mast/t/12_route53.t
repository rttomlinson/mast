use v5.030;
use strictures 2;

use Test::More;
use File::Slurp;
use JSON::PP;
use UUID::Random;

use Mast::Cloud::Spec;
use Mast::Deploy::DNS;

use lib 't/lib';
use AWS::MockCLIWrapper;

my $cloud_spec_json = read_file "t/data/spec/bar-baz-v1_0.json";
my $contexts = ["staging", "standby"];
my $cloud_spec_obj = Mast::Cloud::Spec->new(
  contexts => $contexts,
  cloud_spec_json => $cloud_spec_json,
);

my ($zones, $load_balancers, %records, %changes);

eval join '', <DATA>;

sub generate_change {
  my $id = '/change/' . uc(UUID::Random::generate =~ s/-//gr);

  return $changes{$id} = {
    Id => $id,
    Status => 'PENDING',
    SubmittedAt => `date -R`,
    _counter => 2,
  };
}

sub get_change {
  my ($id) = @_;

  my $change = $changes{$id} // ($changes{$id} = generate_change);

  $change->{Status} = 'INSYNC' if $change->{_counter} <= 0;
  $change->{_counter} -= 1;

  return $change;
}

sub get_zone_by_domain {
  my ($domain, $private) = @_;

  $domain =~ s/\.+$//;

  my $hosted_zones = $zones->{HostedZones};

  my ($zone)
    = grep { $_->{Name} eq "$domain." && $_->{Config}->{PrivateZone} == $private }
           @$hosted_zones;
  
  return $zone;
}

sub get_records_by_domain {
  my $zone = get_zone_by_domain(@_);

  return $records{$zone->{Id}};
}

my $aws = AWS::MockCLIWrapper->new(
  aws_region => 'us-east-1',
  actors => {
    elbv2 => {
      'describe-load-balancers' => sub { $load_balancers },
    },
    route53 => {
      'list-hosted-zones-by-name' => sub { $zones },
      'list-resource-record-sets' => sub {
        my ($self, $params) = @_;

        my $zone_id = $params->{'hosted-zone-id'};
        my $query = $params->{query};

        # We only support lookup by name at this point
        if (my ($fqdn) = $query =~ m|Name\s*==\s*'([^']+)'|) {
          my ($host, $domain) = $fqdn =~ m|^([^.]+)\.(.+)$|;
          my $record;

          for my $private (JSON::PP::true, JSON::PP::false) {
            my $zone = get_zone_by_domain($domain, $private);

            next unless $zone;

            $record = $records{$zone->{Id}}->{$host};

            last if $record;
          }

          return $record ? [$record] : [];
        }
        else {
          die "Unsupported query: $query";
        }
      },
      'change-resource-record-sets' => sub {
        my ($self, $params) = @_;

        my $zone_id = $params->{'hosted-zone-id'};
        my $change_batch = decode_json $params->{'change-batch'};
        my $changes = $change_batch->{Changes};

        for my $change (@$changes) {
          my $action = $change->{Action};
          my $recordset = $change->{ResourceRecordSet};
          my $name = $recordset->{Name} =~ s#\..+$##r;

          my $zone = $records{$zone_id} // ($records{$zone_id} = {});
          my $record = $zone->{$name};

          if ($action eq 'CREATE') {
            die "An error occurred (InvalidChangeBatch) when calling the " .
                "ChangeResourceRecordSets operation: [Tried to create resource record set " .
                "[name='new-record-name.foo.com.', type='A'] but it already exists]"
                  if $record;
            
            $zone->{$name} = $recordset;
          }
          elsif ($action eq 'UPSERT') {
            $zone->{$name} = $recordset;
          }
          elsif ($action eq 'DELETE') {
            die "An error occurred (InvalidChangeBatch) when calling the " .
                "ChangeResourceRecordSets operation: [Tried to delete resource record set " .
                "[name='new-record-name.foo.com.', type='A'] but it does not exist]"
                  unless $record;

            delete $zone->{$name};
          }
        }

        return {
          ChangeInfo => generate_change,
        };
      },
      'get-change' => sub {
        my ($self, $params) = @_;
        
        return {
          ChangeInfo => get_change($params->{id})
        };
      },
    },
  },
);

my $step = Mast::Deploy::DNS->new(
  aws => $aws,
  cloud_spec => $cloud_spec_obj,
  poll_interval => 0,
  log => sub {},
);

my $want_recordset = {
  Name => 'new-record-name.foo.com.',
  Type => 'A',
  AliasTarget => {
    HostedZoneId => 'FOOBAROO',
    DNSName => 'foo-com-123456.us-east-1.elb.amazonaws.com',
    EvaluateTargetHealth => \1,
  },
};

{
  eval { $step->create_dns_records };

  is "$@", "", "initial create no exception";

  my $zone = get_records_by_domain('foo.com', JSON::PP::true);

  is_deeply $zone->{'new-record-name'}, $want_recordset, "initial create record";
}

{
  eval { $step->create_dns_records };

  like "$@", qr/InvalidChangeBatch.*already exists/, "create throws exception when allowExisting == false";
}

{
  $cloud_spec_obj->{spec}->{aws}->{route53}->[0]->{allowExisting} = JSON::PP::true;

  eval { $step->create_dns_records };

  is "$@", "", "create no exception when allowExisting == true";

  my $zone = get_records_by_domain('foo.com', JSON::PP::true);

  is_deeply $zone->{'new-record-name'}, $want_recordset, "record still the same";
}

{
  eval { $step->delete_dns_records };

  is "$@", "", "first delete no exception";

  my $zone = get_records_by_domain('foo.com', JSON::PP::true);

  is exists($zone->{'new-record-name'}), !1, "record deleted";
}

{
  eval { $step->delete_dns_records };

  is "$@", "", "second delete no exception";

  my $zone = get_records_by_domain('foo.com', JSON::PP::true);

  is exists($zone->{'new-record-name'}), !1, "record still deleted";
}

done_testing;

__DATA__
$zones = decode_json << '__END_JSON__';
{
    "HostedZones": [
        {
            "Id": "/hostedzone/Z02935192T1QQ40PR3EHF",
            "Name": "foo.com.",
            "Config": {
                "PrivateZone": false
            },
            "ResourceRecordSetCount": 3
        },
        {
            "Id": "/hostedzone/Z0471732DU0REMYBYYU2",
            "Name": "foo.com.",
            "Config": {
                "PrivateZone": true
            },
            "ResourceRecordSetCount": 115
        }
    ],
    "DNSName": "foo.com",
    "IsTruncated": true,
    "NextDNSName": "bar.com.",
    "NextHostedZoneId": "Z00556613AQRLE6JPZAM7",
    "MaxItems": "2"
}
__END_JSON__

$load_balancers = decode_json <<'__END_JSON__';
{
    "LoadBalancers": [
        {
            "LoadBalancerArn": "arn:aws:elasticloadbalancing:us-east-1:12345678:loadbalancer/app/foo-com/1234567",
            "DNSName": "foo-com-123456.us-east-1.elb.amazonaws.com",
            "CanonicalHostedZoneId": "FOOBAROO",
            "CreatedTime": "2022-03-25T19:21:28.850000+00:00",
            "LoadBalancerName": "foo-com",
            "Scheme": "internal",
            "VpcId": "vpc-123456",
            "State": {
                "Code": "active"
            },
            "Type": "application",
            "AvailabilityZones": [
                {
                    "ZoneName": "us-east-1a",
                    "SubnetId": "subnet-12345",
                    "LoadBalancerAddresses": []
                }
            ],
            "SecurityGroups": [
                "sg-12345678"
            ],
            "IpAddressType": "ipv4"
        }
    ]
}
__END_JSON__

