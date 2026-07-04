#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::verify_single_sets

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(verify_single_sets);

use_ok('Utilities');
can_ok( 'Utilities', 'verify_single_sets' );

exit 0;
