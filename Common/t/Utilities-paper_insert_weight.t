#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::paper_insert_weight

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(paper_insert_weight);

use_ok('Utilities');
can_ok( 'Utilities', 'paper_insert_weight' );

exit 0;
