package DupCheck_Utils;
################################################################################
# Utility sub(s) for duplicate_check database queries during conversion
################################################################################
use 5.010;

use strict;
use warnings;
use Data::Dumper;

use lib_CCS(
	GPD       => '3.00',
	JEF       => '1.00',
	JobEngine => '1.00',
	local =>
		[ 'Modules', 'Modules/Processors', 'Modules/BusinessRules', 'Modules/Renders', 'Modules/Utils', '../Common', ],
	others => [
		$ENV{CCS_RESOURCE} . '/Global/Std',
		$ENV{CCS_RESOURCE} . '/Regional',
		$ENV{CCS_RESOURCE} . '/Regional/<lib_ccs_region>/Finalist/5.10',
		$ENV{CCS_RESOURCE} . '/Regional/NA/Library',

	],
);

use Logger::Log;
use Time::localtime;

use NA::Std::Paths;
use GPD;
use ConfigReader;
use CcsDb;

use ISO_Utils;

use Memoize;

sub account_lookup {
	my ( $jobbag, %transaction_obj ) = @_;

	my $Config     = ConfigReader->new('dupchecks.ini');
	my $db_type    = 'SQL';
	my $sql_server = $Config->get_config( 'db', 'sql_server' );
	my $db         = $Config->get_config( 'db', 'db' );
	my $o_db       = CcsDb->open( { type => $db_type, source => $sql_server, init_cat => $db } );

	my %fields;

	my ( $status, $reason_code, $business_reason ) = ( undef, undef, undef );
	my $temp_run_no         = '000000000';
	my $dupcheck_reportfile = '145BM0100_Duplicate_Check_' . $temp_run_no . '.csv';
	my $files_with_dup      = '';
	my $enc_transit_number;

	if ( !defined $transaction_obj{transit_number} ) {
		# routing number is not in pain001 and is undef
		return ( 'CH21', $transaction_obj{acct_no}, undef, undef );
	}

	if ( '121100782' eq $transaction_obj{transit_number} ) {
		$transaction_obj{transit_number} = '0000000000';
	}

	# get the bank details info first
	$jobbag->{bank_details_ini} = CcsCommon::ini2h( $ENV{CCS_SETTINGS} . '/BankDetails.ini' );

	if ( exists $jobbag->{bank_details_ini}{ $transaction_obj{transit_number} }
		&& $jobbag->{bank_details_ini}{ $transaction_obj{transit_number} } )
	{
		$enc_transit_number = $transaction_obj{transit_number};
	}
	else {
		# get the transformed routing number from enCompass2
		$enc_transit_number =
			eval { transform_routing_number( $transaction_obj{transit_number}, $transaction_obj{acct_no} ); };

		if ($@) {
			return ( 'CH21', $transaction_obj{acct_no}, undef, $@ );
		}
		elsif ( !defined $enc_transit_number ) {
			return ( 'NARR', $transaction_obj{acct_no}, undef, undef );
		}
	}

	( my $temp_chk_number  = $transaction_obj{check_no} ) =~ s/^\s+|\s+$//g;
	( my $temp_rout_number = $enc_transit_number ) =~ s/^\s+|\s+$//g;
	( my $temp_acct_number = $transaction_obj{acct_no} ) =~ s/^\s+|\s+$//g;
	( my $temp_ccs_id      = $transaction_obj{ccs_endtoend_id} ) =~ s/^\s+|\s+$//g;

	$fields{transit_number} = $temp_rout_number;
	$fields{account_number} = $temp_acct_number;
	$fields{cheque_number}  = $temp_chk_number;

	my $return_value;
	if ( 'DupCheckPreProcessor' eq $transaction_obj{package} ) {
		$return_value = eval { $o_db->exec_select_sp( "is_chq_a_dup", CcsDb::fields_to_strfields( \%fields ) ); };
	}

	if ( $@ && 'DupCheckPreProcessor' eq $transaction_obj{package} )
	{    # we only want to check this in DupCheckPreProcessor
		if ( length $transaction_obj{check_no} > 10 ) {
			$status          = 'RJCT';
			$reason_code     = 'NARR';
			$business_reason = 'Cheque Number exceeds 10 digits';

			push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
				{
				payment_id      => $transaction_obj{payment_id},
				status          => $status,
				reason_code     => $reason_code,
				check_amount    => $transaction_obj{check_amount},
				currency        => $transaction_obj{currency},
				transaction_id  => $transaction_obj{transaction_id},
				business_reason => $business_reason,
				check_number    => $transaction_obj{check_no},
				account_number  => $transaction_obj{acct_no},
				routing_number  => $enc_transit_number,
				ccs_endtoend_id => $transaction_obj{ccs_endtoend_id},
				check_date      => $transaction_obj{check_date},
				};

			# increment overall count
			$jobbag->{reject}++;
			$jobbag->{reject_chk_amount} =
				sprintf( "%.2f", ( $jobbag->{reject_chk_amount} || 0 ) + $transaction_obj{check_amount} );

			#increment transaction-level count and accumulated check amounts
			$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
			$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
				( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) + $transaction_obj{check_amount} );

			$jobbag->{reject_type}{transaction}++;
		}
	}
	elsif ($return_value) {

		# output to console and duplicate_check Excel error report
		print "\nDuplicate check found in AA DB:\nCheck details:\n"
			. "Check number - $transaction_obj{check_no}\nCheck amount - $transaction_obj{check_amount}\nPayee - $transaction_obj{payee}\nFile - $transaction_obj{file_name}\n ";

		print "\nDuplicate check database details:\n" . Dumper( \%fields ) . "\n" . Dumper( \$return_value ) . "\n";

		my $needs_header = 1;
		if ( -e $dupcheck_reportfile && -s $dupcheck_reportfile ) {
			$needs_header = 0;
		}
		open my $DUPFILE, '>>', $dupcheck_reportfile
			or Utils::JEF_Exception::terminate("\nFailed to open $dupcheck_reportfile : $!");
		if ($needs_header) {
			# header
			print $DUPFILE "Check Number,Check Amount,Payee,Input File\n";
		}

		$files_with_dup .= $jobbag->{iso_xml_file} . "\n"
			if ( $files_with_dup !~ /$transaction_obj{file_name}/i );

		print $DUPFILE $transaction_obj{check_no} . ','
			. $transaction_obj{check_amount} . ','
			. $transaction_obj{payee} . ','
			. $transaction_obj{file_name} . "\n";

		close $DUPFILE;

		# attach the file to the jobbag. This will be used in ConverterPostProcessor.
		$jobbag->{'dupcheck_reportfile'} = $dupcheck_reportfile;

		# process the RJCT since it is a database hit
		$jobbag->{'Duplicate_checks'}{ $transaction_obj{ccs_endtoend_id} }++;    # from the file
		$jobbag->{rejected}{ $transaction_obj{ccs_endtoend_id} }++;

		$status      = 'RJCT';
		$reason_code = 'DUPL';
		$business_reason =
			"Duplicate cheque found: $transaction_obj{check_no} was already processed (within last year) in data file";
		push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
			{
			payment_id      => $transaction_obj{payment_id},
			status          => $status,
			reason_code     => $reason_code,
			check_amount    => $transaction_obj{check_amount},
			currency        => $transaction_obj{currency},
			transaction_id  => $transaction_obj{transaction_id},
			business_reason => $business_reason,
			check_number    => $transaction_obj{check_no},
			account_number  => $transaction_obj{acct_no},
			routing_number  => $enc_transit_number,
			ccs_endtoend_id => $transaction_obj{ccs_endtoend_id},
			check_date      => $transaction_obj{check_date},
			};

		# increment overall count
		$jobbag->{reject}++;
		$jobbag->{reject_chk_amount} =
			sprintf( "%.2f", ( $jobbag->{reject_chk_amount} || 0 ) + $transaction_obj{check_amount} );

		#increment transaction-level count and accumulated check amounts
		$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
		$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
			( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) + $transaction_obj{check_amount} );

		$jobbag->{reject_type}{transaction}++;

	}

	$o_db->close;

	$status = 'ACCP' if !defined $status;

	return ( $status, $transaction_obj{acct_no}, $enc_transit_number, undef );
}

memoize('transform_routing_number');

sub transform_routing_number {
	my ( $file_routing_number, $account_number ) = @_;

	my $check_routing_number;
	my $enCompass2_details;

	$enCompass2_details = eval { _enCompass2_details($account_number); };

	if ($@) {
		$check_routing_number = undef;
		Utils::JEF_Exception::terminate($@);
	}
	else {
		$check_routing_number = $enCompass2_details->{routing_number};
	}

	return $check_routing_number;

}

sub _enCompass2_details {
	my ($account_number) = @_;

	my $ec_details = {};

	my $dsn =
		SOAP::Lite->proxy( CcsCommon::get_setting( 'ENCOMPASS', 'encompass2_appadmin' ), timeout => 60 )
		->on_action( sub { $_[0] . $_[1] } )->on_fault( \&_soap_fault_handler )
		->call( SOAP::Data->name('GetConnectionString')->attr( { xmlns => "http://tempuri.org/" } ) =>
			( SOAP::Data->name( 'siteName' => 'Toronto' ), SOAP::Data->name( 'appName' => 'encompass2' ) ) )->result();

	my %dsnDetails = map { /(.*)=(.*)/ ? ( lc $1 => $2 ) : () } split( ';', $dsn );
	$ec_details->{db_server} = $dsnDetails{'data source'};
	$ec_details->{db_name}   = $dsnDetails{'initial catalog'};
	$ec_details->{db_uid}    = $dsnDetails{'user id'};
	$ec_details->{db_pwd}    = $dsnDetails{'password'};

	my $o_db = CcsDb->open(
		{
			type     => 'SQL_USER',
			source   => $ec_details->{db_server},
			init_cat => $ec_details->{db_name},
			userid   => $ec_details->{db_uid},
			password => $ec_details->{db_pwd}
		}
	);

	my $tblSets =
		$o_db->select_records( 'tblSets', [ 'ID', 'Name' ], { NodeType => 'BMO_ISO', Name => $account_number } );

	if ( !$tblSets ) {
		Utils::JEF_Exception::terminate(
			"No enCompass2 records were returned from tblSets for account number '$account_number'");
	}

	my %enCompass2_mapping = (
		'company_name'       => 'company_name',
		'courier_account_no' => 'courier_account_number',
		'bill_to_name'       => 'courier_bill_to_name',
		'bill_to_street'     => 'courier_bill_to_street',
		'bill_to_city'       => 'courier_bill_to_city',
		'bill_to_state'      => 'courier_bill_to_state',
		'bill_to_zipcode'    => 'courier_bill_to_zipcode',
		'courier_option'     => 'courier_option',
		'name'               => 'special_handling_name',
		'attn'               => 'special_handling_attention',
		'street_addr'        => 'special_handling_street_address',
		'city'               => 'special_handling_city',
		'state'              => 'special_handling_state',
		'zip_code'           => 'special_handling_zip_code',
		'email_username'     => 'email_username',
		'email_domain'       => 'email_domain',
		'email_extension'    => 'email_extension',
		'zipfile_password'   => 'zipfile_password',
		'routing_number'     => 'routing_number',
	);

	my %enCompass2_details;

	foreach my $id ( @{$tblSets} ) {

		my $tblSetData = $o_db->select_records( 'tblSetData', ['Category, Setting, Value'], { ID => $id->{ID} } );

		if ($tblSetData) {
			foreach my $rec ( @{$tblSetData} ) {

				if ( $rec->{Setting} =~ /check_amount_rule/i ) {
					# remove the $ and , from the amount that's in enCompass2 so it can be compared
					# with the dollar amount of the check
					( $enCompass2_details{check_amount_rule} = $rec->{Value} ) =~ s/\$|\,//g;
				}
				else {
					if ( $enCompass2_mapping{ $rec->{Setting} } ) {
						$enCompass2_details{ $rec->{Setting} } = $rec->{Value};
					}

				}

			}
		}
	}

	return \%enCompass2_details;

}

sub _soap_fault_handler {
	my ( $soap, $response ) = @_;

	my $err;
	if ( ref($response) and $response->faultstring ) {
		$err = "SOAP FAULT: " . $response->faultstring;
	}
	else {
		$err = "TRANSPORT ERROR: " . $soap->transport->status;
	}
	print "ERROR: $err\n";

	print "Dumping \$response\n";
	print Dumper($response);

	print "Dumping soap->transport\n";
	print Dumper( $soap->transport );
	die;
}

1;
