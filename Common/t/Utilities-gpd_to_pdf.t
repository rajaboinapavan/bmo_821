#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::gpd_to_pdf

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(gpd_to_pdf);

use_ok('Utilities');
can_ok( 'Utilities', 'gpd_to_pdf' );

exit 0;
