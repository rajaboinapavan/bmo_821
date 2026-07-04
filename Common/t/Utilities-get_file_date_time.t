#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::get_file_date_time

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(get_file_date_time);

use_ok('Utilities');
can_ok( 'Utilities', 'get_file_date_time' );

exit 0;
