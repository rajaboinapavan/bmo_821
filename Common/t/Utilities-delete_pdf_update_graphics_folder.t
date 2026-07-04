#!C:/Perl5.10.1/bin/perl.exe
#
# test Utilities::delete_pdf_update_graphics_folder

use 5.010;

use strict;
use warnings;

use Data::Dumper;

use Test::More;
plan tests => 2;

use FindBin qw($Bin);
use lib "$Bin/..";
use Utilities qw(delete_pdf_update_graphics_folder);

use_ok('Utilities');
can_ok( 'Utilities', 'delete_pdf_update_graphics_folder' );

exit 0;
