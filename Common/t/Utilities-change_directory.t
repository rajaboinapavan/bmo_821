#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::change_directory

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(change_directory);

use_ok('Utilities');
can_ok( 'Utilities', 'change_directory' );

exit 0;
