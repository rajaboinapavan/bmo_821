#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::zipFiles

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(zipFiles);

use_ok('Utilities');
can_ok( 'Utilities', 'zipFiles' );

exit 0;
