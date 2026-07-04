#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::load_documents

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(load_documents);

use_ok('Utilities');
can_ok( 'Utilities', 'load_documents' );

exit 0;
