#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::add_reporting_set_tags

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(add_reporting_set_tags);

use_ok('Utilities');
can_ok( 'Utilities', 'add_reporting_set_tags' );

exit 0;
