use v5.030;
use warnings;
no warnings 'uninitialized';

use Test::More;

use Mast::Service::Spec 'collapser';

my $tests = eval join '', <DATA>;
for my $test (@$tests) {
  my ($name, $env, $input, $xcpt, $want, $contexts)
    = @$test{qw(name env input exception want contexts)};
  
  if (not ref $env) {
    $want = {
      $env => $want,
    };
    unshift(@{$contexts}, $env);
    my $have = eval { collapser $contexts, $input };
    is "$@", "$xcpt", "$name $contexts exception";
    is_deeply $have, $want->{$env}, "$name $contexts output";

  } else {
    for my $e (@$env) {
      my @new_contexts = ();
      @new_contexts = @$contexts if (ref $contexts);
      unshift(@new_contexts, $e);
      my $have = eval { collapser \@new_contexts, $input };
      is "$@", "$xcpt", "$name $e exception";
      is_deeply $have, $want->{$e}, "$name $e output";
    }
  }

  
}

done_testing;

__DATA__
# line 40
[{
  name => 'deep',
  env => 'bar',
  input => {
    foo => {
      bar => [{
        qux => [qw(frobbe throbbe)],
        blorb => 'plugh',
      }],
    },
  },
  want => {
    foo => [{
        qux => [qw(frobbe throbbe)],
        blorb => 'plugh',
    }],
  },
},{
  name => 'pass-through',
  env => 'prestaging',
  input => {
    foo => {
      bar => [{
        qux => [qw(frobbe throbbe)],
        blorb => 'plugh',
      }],
    },
  },
  want => {
    foo => {
      bar => [{
        qux => [qw(frobbe throbbe)],
        blorb => 'plugh',
      }],
    },
  },
}, {
  name => 'top',
  env => 'staging',
  input => {
    prestaging => {
      foo => 'prestaging',
    },
    staging => {
      foo => 'staging',
    },
    production => {
      foo => 'production',
    },
  },
  want => {
    foo => 'staging',
  },
}, {
  name => 'deep-2',
  env => [qw(prestaging staging production)],
  input => {
    foo => [{
      kribble => {
        prestaging => {
          bar => [{
            prestaging => ['prestaging'],
            staging => ['staging'],
            production => ['production'],
          }],
        },
        staging => {
          qux => [{
            prestaging => ['prestaging'],
            staging => ['staging'],
            production => ['production'],
          }],
        },
        production => {
          frob => [{
            prestaging => 'prestaging',
            staging => 'staging',
            production => 'production',
          }],
        },
      },
      krabble => [{
        prestaging => 'prestaging',
        staging => 'staging',
        production => 'production',
      }],
    }],
  },
  want => {
    prestaging => {
      foo => [{
        kribble => {
          bar => [['prestaging']],
        },
        krabble => ['prestaging'],
      }],
    },
    staging => {
      foo => [{
        kribble => {
          qux => [['staging']],
        },
        krabble => ['staging'],
      }],
    },
    production => {
      foo => [{
        kribble => {
          frob => ['production'],
        },
        krabble => ['production'],
      }],
    },
  },
}, {
  name => 'replace-one-level',
  contexts => ["hello"],
  input => {
      "jello" => "world",
      "foo" => {
          "hello" => "bar"
      }
  },
  want => {
      "jello" => "world",
      "foo" => "bar"
  }
}, {
  name => 'two-contexts',
  contexts => ["hello", "jelly"],
  input => {
      "jello" => "world",
      "foo" => {
          "hello" => "bar"
      },
      "jerry" => {
          "hello" => {
              "jeorge" => {
                  "jelly" => "roll"
              }
          }
      }
  },
  want => {
      "jello" => "world",
      "foo" => "bar",
      "jerry" => {
          "jeorge" => "roll"
      },
  }
}, {
  name => 'replace-one-level',
  contexts => ["hello"],
  input => {
      "jello" => "world",
      "foo" => {
          "hello" => "bar"
      }
  },
  want => {
      "jello" => "world",
      "foo" => "bar"
  }
},{
  name => 'two-contexts-with-env',
  env => "prestaging",
  contexts => ["hello", "jelly"],
  input => {
      "hi" => {
        "prestaging" => {
          "jelly" => [1, 2, 3]
        }
      },
      "jello" => "world",
      "foo" => {
          "hello" => "bar"
      },
      "jerry" => {
          "hello" => {
              "jeorge" => {
                  "jelly" => "roll"
              }
          }
      }
  },
  want => {
      "hi" => [1, 2, 3],
      "jello" => "world",
      "foo" => "bar",
      "jerry" => {
          "jeorge" => "roll"
      },
  }
},{
  name => 'two-contexts-with-duplicate-env-in-context',
  env => "prestaging",
  contexts => ["prestaging", "hello", "jelly"],
  input => {
      "hi" => {
        "prestaging" => {
          "jelly" => [1, 2, 3]
        }
      },
      "jello" => "world",
      "foo" => {
          "hello" => "bar"
      },
      "jerry" => {
          "hello" => {
              "jeorge" => {
                  "jelly" => "roll"
              }
          }
      }
  },
  want => {
      "hi" => [1, 2, 3],
      "jello" => "world",
      "foo" => "bar",
      "jerry" => {
          "jeorge" => "roll"
      },
  }
}]
