#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::_getOunceRangeForUSPSFromGrams

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(_getOunceRangeForUSPSFromGrams);

use_ok('Utilities');
can_ok( 'Utilities', '_getOunceRangeForUSPSFromGrams' );

exit 0;
