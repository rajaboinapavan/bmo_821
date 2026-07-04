#!/usr/bin/perl

package DBHelper;

use strict;
use warnings;

use lib $ENV{CCS_RESOURCE};
use lib_CCS others => [
	"$ENV{CCS_RESOURCE}/Global/Std", "$ENV{CCS_RESOURCE}/Global/enCompass/Modules/DAL",
	"$ENV{CCS_RESOURCE}/Regional/NA/Perl/5.10/site/lib",
];

use DAL;

sub create_encompass_connection {
	my ($args) = @_;
	my $retries = 1;
	my $retry_comp = $args->{db_retries}    // 1;
	my $retry_time = $args->{db_retry_time} // 1;
	my $dsnDetails = $args->{dsnDetails};

	my $dal = DAL->new();

	$dal->set_username_and_password( $dsnDetails->{'user id'}, $dsnDetails->{'password'} );
	_connection_retry( $dal, $retry_comp, $retry_time, $retries, $dsnDetails );

	return $dal;
}

sub _connection_retry {
	my ( $conn, $retry_comp, $retry_time, $retries, $dsn_info ) = @_;

	eval { $conn->create_db_connection( $dsn_info->{'data source'}, $dsn_info->{'initial catalog'} ); };
	if ( $@ && $retry_comp < $retries ) {
		sleep($retry_time);
		$retries++;
		_connection_retry( $conn, $retry_comp, $retry_time, $retries, $dsn_info );
	}
	elsif ($@) {
		die "DB CONNECTION ERROR: $@";
	}

	return;
}

### Look up the configuration in the encompass registry given a specific encompass key.
sub get_encompass_config {
	my ( $encompass_conn, $account_number ) = @_;

	my $node = $encompass_conn->get_node_type_id( 'BMO_ISO', $account_number );
	die "Can't find Encompass node for account number $account_number" if !$node;

	my $branch = $encompass_conn->get_entire_branch($node);
	die "Cant get node settings for account number $account_number " if !$branch;

	my $category = $encompass_conn->get_category_settings($branch);
	die "Can't get category settings for account number $account_number" if !$category;

	return $category->{$node};
}

1;
