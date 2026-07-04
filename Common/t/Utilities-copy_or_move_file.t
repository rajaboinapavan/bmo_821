#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::copy_or_move_file

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(copy_or_move_file);

use_ok('Utilities');
can_ok( 'Utilities', 'copy_or_move_file' );

exit 0;
