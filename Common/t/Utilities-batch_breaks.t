#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::batch_breaks

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(batch_breaks);

use_ok('Utilities');
can_ok( 'Utilities', 'batch_breaks' );

exit 0;
