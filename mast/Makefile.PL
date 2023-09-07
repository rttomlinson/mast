use strict;
use warnings;

use ExtUtils::MakeMaker;

our @bin_files = map { chomp; "bin/$_" } qx{ls -1 bin/};

package MY;

sub test {
  my $text = shift->SUPER::test(@_);
  $text =~ s/^test :: (.*)$/test :: $1 bin_syntax_checks/m;

  $text .= <<'END';
bin_syntax_checks ::
END

  $text .= qq|\tPERL_DL_NONLAZY=1 \$(FULLPERLRUN) "-I\$(INST_LIB)" "-I\$(INST_ARCHLIB)" -c $_\n|
    for @bin_files;

  return $text;
}

package main;

WriteMakefile(
  NAME => 'Mast',
  VERSION => '1.0',
  # DO NOT ADD DEPENDENCIES HERE. ADD THEM IN DOCKERFILE INSTEAD.
  TEST_REQUIRES => {
  },
  PREREQ_PM => {
  },
  MIN_PERL_VERSION => 5.030,
  EXE_FILES => [@bin_files],
);
