package ConverterBusinessRules;

use 5.010;

use strict;
use warnings;

use base qw(GenericBusinessRule);
use Data::Dumper;

use lib $ENV{'CCS_RESOURCE'} . '/Regional';
use NA::Std::CountryCodes;
use NA::Std::Paths;
use CcsCommon;
use Utils::DBHelper;
use XML::Twig;
use DupCheck_Utils;

my %dsnDetails;
my $enCompass2_details;
my @acct_nos;           # ALL acct_nos including duplicate
my %acct_nos_unique;    # captures UNIQUE account numbers

BEGIN {
	my $dsn = eval {
		SOAP::Lite->proxy( CcsCommon::get_setting( 'ENCOMPASS', 'encompass2_appadmin' ), timeout => 60 )
			->on_action( sub { $_[0] . $_[1] } )->on_fault( \&_soap_fault_handler )
			->call( SOAP::Data->name('GetConnectionString')->attr( { xmlns => "http://tempuri.org/" } ) =>
				( SOAP::Data->name( 'siteName' => 'Toronto' ), SOAP::Data->name( 'appName' => 'encompass2' ) ) )
			->result();
	};
	if ( $@ =~ /TRANSPORT ERROR/ ) {
		Utils::JEF_Exception::terminate("SOAP Error occurred: $@");
	}
	%dsnDetails = map { /(.*)=(.*)/ ? ( lc $1 => $2 ) : () } split( ';', $dsn );
}

sub init_rule {
	my ( $this, $jobbag ) = @_;

	$jobbag->{bank_details_ini} = CcsCommon::ini2h( $ENV{CCS_SETTINGS} . '/BankDetails.ini' );

	return 1;
}

sub execute_rule {
	my ( $this, $raw_set, $jobbag, $rule_set ) = @_;

	my $tag = $raw_set->{nodeName};

	if ( $tag eq 'GrpHdr' ) {
		$jobbag->{file_information}{number_of_checks} = $raw_set->{NbOfTxs};
		$jobbag->{file_information}{check_total}      = $raw_set->{CtrlSum};
		$jobbag->{file_information}{CreDtTm}          = $raw_set->{CreDtTm};
		# WR565
		$jobbag->{file_information}{party_id} = $raw_set->{InitgPty}{Id}{OrgId}{Othr}{Id};
	}

	if ( $tag eq 'PmtInf' ) {

		$jobbag->{pmt_inf}{group} = {
			status          => undef,
			reason_code     => undef,
			business_reason => undef,
		};

		$jobbag->{payer_details}{transaction_id}   = $raw_set->{PmtInfId};
		$jobbag->{check_details}{check_date}       = $raw_set->{ReqdExctnDt} || '';
		$jobbag->{check_details}{control_sum}      = $raw_set->{CtrlSum};
		$jobbag->{check_details}{number_of_checks} = $raw_set->{NbOfTxs};
	}

	if ( $tag eq 'Dbtr' ) {

		$jobbag->{payer_details}{name}            = $raw_set->{Nm};
		$jobbag->{payer_details}{building_number} = $raw_set->{PstlAdr}{BldgNb};
		$jobbag->{payer_details}{street_name}     = $raw_set->{PstlAdr}{StrtNm};
		$jobbag->{payer_details}{city}            = $raw_set->{PstlAdr}{TwnNm};
		$jobbag->{payer_details}{state}           = $raw_set->{PstlAdr}{CtrySubDvsn};
		$jobbag->{payer_details}{zip_code}        = $raw_set->{PstlAdr}{PstCd};

	}

	if ( $tag eq 'DbtrAcct' ) {
		#clear if previously set
		$jobbag->{pmt_inf}{undefined}{account_number} = 0;

		if (    exists $raw_set->{Id}
			and ref $raw_set->{Id}
			and exists $raw_set->{Id}{Othr}
			and ref $raw_set->{Id}{Othr}
			and exists $raw_set->{Id}{Othr}{Id} )
		{
			$jobbag->{check_details}{account_number} = $raw_set->{Id}{Othr}{Id};
		}
		else {
			$jobbag->{check_details}{account_number} = '0000000000';
			$jobbag->{pmt_inf}{undefined}{account_number} = 1;
		}
	}

	if ( $tag eq 'DbtrAgt' ) {
		#clear if previously set
		$jobbag->{pmt_inf}{undefined}{routing_number} = 0;

		if (    exists $raw_set->{FinInstnId}
			and ref $raw_set->{FinInstnId}
			and exists $raw_set->{FinInstnId}{ClrSysMmbId}
			and not ref $raw_set->{FinInstnId}{ClrSysMmbId} )
		{
			$jobbag->{check_details}{routing_number} = undef;
			$jobbag->{pmt_inf}{undefined}{routing_number} = 1;
		}
		elsif ( exists $raw_set->{FinInstnId}
			and ref $raw_set->{FinInstnId}
			and exists $raw_set->{FinInstnId}{ClrSysMmbId}
			and ref $raw_set->{FinInstnId}{ClrSysMmbId}
			and exists $raw_set->{FinInstnId}{ClrSysMmbId}{MmbId}
			and not $raw_set->{FinInstnId}{ClrSysMmbId}{MmbId} )
		{
			$jobbag->{check_details}{routing_number} = undef;
			$jobbag->{pmt_inf}{undefined}{routing_number} = 1;
		}
		elsif ( exists $raw_set->{FinInstnId}
			and ref $raw_set->{FinInstnId}
			and exists $raw_set->{FinInstnId}{ClrSysMmbId}
			and ref $raw_set->{FinInstnId}{ClrSysMmbId}
			and exists $raw_set->{FinInstnId}{ClrSysMmbId}{MmbId}
			and $raw_set->{FinInstnId}{ClrSysMmbId}{MmbId} )
		{
			if ( '121100782' eq $raw_set->{FinInstnId}{ClrSysMmbId}{MmbId} ) {
				$jobbag->{check_details}{routing_number} = '0000000000';
			}
			else {
				$jobbag->{check_details}{routing_number} = $raw_set->{FinInstnId}{ClrSysMmbId}{MmbId};
			}
		}
	}

	if ( $tag eq 'CdtTrfTxInf' ) {
		my ( $status, $reason_code, $business_reason );

		$rule_set->{addressee_details}{name}            = $raw_set->{Cdtr}{Nm};
		$rule_set->{addressee_details}{building_number} = $raw_set->{Cdtr}{PstlAdr}{BldgNb};
		$rule_set->{addressee_details}{street_name}     = $raw_set->{Cdtr}{PstlAdr}{StrtNm};
		$rule_set->{addressee_details}{city}            = $raw_set->{Cdtr}{PstlAdr}{TwnNm};
		$rule_set->{addressee_details}{state}           = $raw_set->{Cdtr}{PstlAdr}{CtrySubDvsn};
		$rule_set->{addressee_details}{zip_code}        = $raw_set->{Cdtr}{PstlAdr}{PstCd};

		# when there are multiple AdrLines nodes in the XML it comes across as an array
		# force this to be an array when there's a single AdrLine so we can use the same code in either case
		if ( defined $raw_set->{Cdtr}{PstlAdr}{AdrLine} and ref $raw_set->{Cdtr}{PstlAdr}{AdrLine} ne 'ARRAY' ) {
			$raw_set->{Cdtr}{PstlAdr}{AdrLine} = [ $raw_set->{Cdtr}{PstlAdr}{AdrLine} ];
		}
		foreach my $adr_line ( @{ $raw_set->{Cdtr}{PstlAdr}{AdrLine} } ) {
			push @{ $rule_set->{addressee_details}{adr_lines} }, "$adr_line";
		}

		if ( '' eq $rule_set->{addressee_details}{street_name} ) {
			if ( @{ $rule_set->{addressee_details}{adr_lines} }[0] ) {
				$rule_set->{addressee_details}{street_name} = @{ $rule_set->{addressee_details}{adr_lines} }[0];
			}
		}

		if ( exists $raw_set->{Cdtr}{PstlAdr}{Ctry} and $raw_set->{Cdtr}{PstlAdr}{Ctry} ne 'US' ) {
			my $country_code =
				  ( length( $raw_set->{Cdtr}{PstlAdr}{Ctry} ) == 2 )
				? ( NA::Std::CountryCodes::iso2to3( $raw_set->{Cdtr}{PstlAdr}{Ctry} ) )
				: ( length( $raw_set->{Cdtr}{PstlAdr}{Ctry} ) == 3 ) ? ( $raw_set->{Cdtr}{PstlAdr}{Ctry} )
				:                                                      '';

			my $country_name =
				  ($country_code)
				? ( NA::Std::CountryCodes::ISOCountryCodeToFullCountryName($country_code) )
				: ( $raw_set->{Cdtr}{PstlAdr}{Ctry} );

			$rule_set->{addressee_details}{country} = $country_name;

		}

		# when there are multiple Ustrd nodes in the XML it comes across as an array
		# force this to be an array when there's a single Ustrd so we can use the same code in either case
		if ( defined $raw_set->{RmtInf}{Ustrd} and ref $raw_set->{RmtInf}{Ustrd} ne 'ARRAY' ) {
			$raw_set->{RmtInf}{Ustrd} = [ $raw_set->{RmtInf}{Ustrd} ];
		}
		foreach my $unstr_element ( @{ $raw_set->{RmtInf}{Ustrd} } ) {
			push @{ $rule_set->{remit_details}{remittance_info} }, "$unstr_element";
		}

		# when there are multiple Strd nodes in the XML it comes across as an array
		# force this to be an array when there's a single Strd so we can use the same code in either case

		if ( defined $raw_set->{RmtInf}{Strd} and ref $raw_set->{RmtInf}{Strd} ne 'ARRAY' ) {
			$raw_set->{RmtInf}{Strd} = [ $raw_set->{RmtInf}{Strd} ];
		}

		foreach my $element ( @{ $raw_set->{RmtInf}{Strd} } ) {

			my $net_amount =
				  $element->{RfrdDocInf}{Tp}{CdOrPrtry}{Cd} eq 'CINV' ? $element->{RfrdDocAmt}{RmtdAmt}{content}
				: $element->{RfrdDocInf}{Tp}{CdOrPrtry}{Cd} eq 'CREN' ? $element->{RfrdDocAmt}{CdtNoteAmt}{content}
				: Utils::JEF_Exception::terminate(
				"Unhandled invoice type: '$element->{RfrdDocInf}{Tp}{CdOrPrtry}{Cd}'");

			push @{ $rule_set->{remit_details}{remittance_table} }, {
				'ref_type'     => $element->{CdtrRefInf}{Tp}{CdOrPrtry}{Prtry},    # WR 576
				'ref_id'       => $element->{CdtrRefInf}{Ref},                     # WR 576
				'ref_number'   => $element->{RfrdDocInf}{Nb},
				'ref_date'     => $element->{RfrdDocInf}{RltdDt},
				'doc_amount'   => $element->{RfrdDocAmt}{DuePyblAmt}{content},
				'disc_amount'  => $element->{RfrdDocAmt}{DscntApldAmt}{content},
				'net_amount'   => $net_amount,
				'invoice_type' => $element->{RfrdDocInf}{Tp}{CdOrPrtry}{Cd},
			};

			push @{ $rule_set->{remit_details}{remittance_table} }, { 'invoice_details' => $element->{AddtlRmtInf} };
		}

		my $mf;
		if ( not exists $raw_set->{ChqInstr} ) {
			$mf = undef;
		}
		elsif ( exists $raw_set->{ChqInstr}
			and ref $raw_set->{ChqInstr}
			and not exists $raw_set->{ChqInstr}{MemoFld} )
		{
			$mf = undef;
		}
		elsif ( exists $raw_set->{ChqInstr}
			and ref $raw_set->{ChqInstr}
			and exists $raw_set->{ChqInstr}{MemoFld}
			and not ref $raw_set->{ChqInstr}{MemoFld} )
		{
			$mf = [ $raw_set->{ChqInstr}{MemoFld} ];
		}
		elsif (
			    exists $raw_set->{ChqInstr}
			and ref $raw_set->{ChqInstr}
			and exists $raw_set->{ChqInstr}{MemoFld}
			and 'ARRAY' eq ref $raw_set->{ChqInstr}{MemoFld}

			)
		{
			$mf = $raw_set->{ChqInstr}{MemoFld};
		}

		if ( 'ARRAY' eq ref $mf ) {
			#clear/set tracking hash
			$jobbag->{memo}{length} = 0;

			my $memo_line  = '';
			my $memo_count = 0;

			foreach my $memo ( @{$mf} ) {
				if ( $memo_count <= 1 ) {
					if ( length($memo) > 35 ) {
						$jobbag->{memo}{length} = 1;
					}
					if ( length($memo) < 1 ) {
						$memo_count++;
						next;
					}
					else {
						$memo_line .= " $memo";
						$memo_count++;
					}
				}
				else {
					next;
				}
			}
			if ( length($memo_line) < 1 ) {
				$rule_set->{check_details}{memo} = undef;
			}
			else {
				$rule_set->{check_details}{memo} = $memo_line;
			}
		}
		else {
			$jobbag->{memo}{length}          = 0;
			$rule_set->{check_details}{memo} = undef;
		}

		#clear if previously set
		$jobbag->{'file_issues'}{undefined}{check_amount} = 0;
		if ( !defined $raw_set->{Amt}{InstdAmt}{content} ) {
			$jobbag->{'file_issues'}{undefined}{check_amount} = 1;
		}
		$rule_set->{check_details}{check_amount} = sprintf( "%.2f", ( $raw_set->{Amt}{InstdAmt}{content} || '0.00' ) );
		$rule_set->{check_details}{check_currency}  = $raw_set->{Amt}{InstdAmt}{Ccy};
		$rule_set->{check_details}{check_date}      = $jobbag->{check_details}{check_date};
		$rule_set->{check_details}{routing_number}  = $jobbag->{check_details}{routing_number};
		$rule_set->{check_details}{pmt_id}          = $raw_set->{PmtId}{EndToEndId};
		$rule_set->{check_details}{ccs_endtoend_id} = $raw_set->{PmtId}{CCS_EndToEndID};

		my $cheque_no;
		if ( not exists $raw_set->{ChqInstr} ) {
			$cheque_no = '';
		}
		elsif ( exists $raw_set->{ChqInstr}
			and not ref $raw_set->{ChqInstr} )
		{
			$cheque_no = '';
		}
		elsif ( exists $raw_set->{ChqInstr}
			and ref $raw_set->{ChqInstr}
			and exists $raw_set->{ChqInstr}{ChqNb}
			and not ref $raw_set->{ChqInstr}{ChqNb} )
		{
			$cheque_no = $raw_set->{ChqInstr}{ChqNb};
		}

		my %transaction_obj;
		$transaction_obj{payment_id}      = $rule_set->{check_details}{pmt_id};
		$transaction_obj{status}          = undef;
		$transaction_obj{reason_code}     = undef;
		$transaction_obj{check_amount}    = $rule_set->{check_details}{check_amount};
		$transaction_obj{currency}        = $rule_set->{check_details}{check_currency};
		$transaction_obj{transaction_id}  = $jobbag->{payer_details}{transaction_id};
		$transaction_obj{business_reason} = undef;
		$transaction_obj{check_no}        = $cheque_no;
		$transaction_obj{payee}           = $rule_set->{addressee_details}{name};
		$transaction_obj{file_name}       = $jobbag->{'orig_xml_file'};
		$transaction_obj{transit_number}  = $rule_set->{check_details}{routing_number};
		$transaction_obj{acct_no}         = $jobbag->{check_details}{account_number};
		$transaction_obj{ccs_endtoend_id} = $rule_set->{check_details}{ccs_endtoend_id};
		$transaction_obj{check_date}      = $rule_set->{check_details}{check_date};
		$transaction_obj{package}         = 'ConverterBusinessRules';

		# read the input file to fetch all unique accounts
		# populate jobbag cache for each of those accounts
		# if there is an error populate the acct_error hash in jobbag
		# eg: missing account number record in enCompass2 DB
		if ( !$jobbag->{file_read_flag} ) {
			_read_acct_numbers( $this, $jobbag );
			$jobbag->{file_read_flag} = 1;

			# remove duplicate account numbers
			%acct_nos_unique = map { $_ => 1 } @acct_nos;

			# build the encompass2 data cache with all the account numbers from the input XML
			# this wil run just once per converter run, due to the flag $file_read_flag
			foreach my $acct_no ( keys(%acct_nos_unique) ) {
				my $db_details = eval { _get_encompass_details( $jobbag, $acct_no ); };
				if ($@) {
					if ( $@ =~ /DB CONNECTION ERROR/ ) {
						Utils::JEF_Exception::terminate("Error connecting to DB: $@");
					}
					elsif ( $@ =~ /uninitialized/i ) {
						Utils::JEF_Exception::terminate("Programmatic Uninitialized error: $@");
					}
					else {
						my $acct = $jobbag->{check_details}{account_number};
						if ( $@ =~ /Can't find Encompass node for account number (\d)+/i ) {
							$acct = sprintf "%010s", $1;
							print "\n No enCompass2 records were returned from tblSets for account number $acct\n";
						}
						elsif ( $@ =~ /panic|Bizarre/i ) {
							# display the issues that comes from Carp::Heavy module
							# error 1 - semi-panic: attempt to dup freed string at ...
							# error 2 - panic: attempt to copy freed scalar 5fc08e4 to 72f8e8c at ...
							# error 3 - Bizarre copy of ARRAY in sassign at ...
							print "\n Carp Heavy error (known): $@";
						}
						else {
							# capture all the other errors we did not capture above
							# we terminate here because we do not know the impact of this error, as yet!
							Utils::JEF_Exception::terminate("Error occurred while fetching data from enCompass2: $@");
						}
						# record the error for this particular $acct
						# that will be used at a later point to consolidate errors
						$jobbag->{acct_error}->{$acct} = $@;
					}
				}
				else {
					$jobbag->{_encompass_data}{$acct_no} = $db_details;
				}
			}    # end of foreach unique accts
		}    # end of IF file_read_flag

		# WR-483: Get the account number transformed to get
		# transformed_acct_num, transformed_rout_num
		# this happens *per account* in the order in PAIN001
		my ( $al_status, $transformed_acct_num, $transformed_rout_num, $err ) = ( undef, undef, undef, undef );

		( $al_status, $transformed_acct_num, $transformed_rout_num, $err ) =
			DupCheck_Utils::account_lookup( $jobbag, %transaction_obj );

		# we are now done with enCompass2 DB cache & DupCheck_Utils
		# let us now consolidate all the errors if occurred
		# the order of precedence of checking errors are,
		#	1. account number missing in enCompass2
		#	2. Routing number missing
		#	3. Transit [Routing] Numbers/MICR Details invalid
		# we will either get an error from DupCheck_Utils (or)
		# we check the acct_error hash from jobbag for account that is not in EC2
		# in either case, we populate the PAIN002 object here
		if ( $err || exists $jobbag->{acct_error}->{$transformed_acct_num} ) {

			$rule_set->{check_details}{account_number} = $jobbag->{check_details}{account_number};
			$rule_set->{check_details}{check_number}   = $cheque_no;

			$status          = 'RJCT';
			$reason_code     = 'CH21';
			$business_reason = 'Account Number is Missing';

			_prep_pain002_object(
				{
					jobbag               => $jobbag,
					ruleset              => $rule_set,
					rawset               => $raw_set,
					status               => $status,
					reason_code          => $reason_code,
					business_reason      => $business_reason,
					transformed_rout_num => $transformed_rout_num,
				}
			);
		}
		elsif ( 'CH21' eq $al_status || 'NARR' eq $al_status ) {
			# set these two as-is since we don't have the routing number
			$rule_set->{check_details}{account_number} = $jobbag->{check_details}{account_number};
			$rule_set->{check_details}{check_number}   = $cheque_no;

			# first clear if previously set
			$jobbag->{pmt_inf}{unsupported}{account_number} = '';
			$jobbag->{pmt_inf}{unsupported}{routing_number} = '';
			$jobbag->{pmt_inf}{unsupported}{check_number}   = '';
			$jobbag->{pmt_inf}{undefined}{routing_number}   = '';

			# now set these values
			$jobbag->{pmt_inf}{unsupported}{account_number} = $jobbag->{check_details}{account_number};
			$jobbag->{pmt_inf}{unsupported}{routing_number} = undef;
			$jobbag->{pmt_inf}{unsupported}{check_number}   = $cheque_no;

			if ( 'CH21' eq $al_status ) {
				$status          = 'RJCT';
				$reason_code     = 'CH21';
				$business_reason = 'Routing Number is  Missing';
			}
			else {
				$status          = 'RJCT';
				$reason_code     = 'NARR';
				$business_reason = 'Transit [Routing] Numbers/MICR Details invalid';
			}

			$jobbag->{acct_error}->{ $jobbag->{check_details}{account_number} } = $business_reason;

			_prep_pain002_object(
				{
					jobbag               => $jobbag,
					ruleset              => $rule_set,
					rawset               => $raw_set,
					status               => $status,
					reason_code          => $reason_code,
					business_reason      => $business_reason,
					transformed_rout_num => $transformed_rout_num,
				}
			);
		}
		else {
			# use routing number returned from account_lookup
			if ( $transformed_rout_num eq '071025661' ) {
				$rule_set->{check_details}{routing_number} = $transformed_rout_num;
				$rule_set->{check_details}{account_number} =
					sprintf( '%10s', $jobbag->{check_details}{account_number} );
				$rule_set->{check_details}{check_number} = sprintf( '%10s', $cheque_no );
			}
			elsif ( $transformed_rout_num eq '071000288' ) {
				$rule_set->{check_details}{routing_number} = $transformed_rout_num;
				$rule_set->{check_details}{account_number} =
					sprintf( '%10s', $jobbag->{check_details}{account_number} );
				$rule_set->{check_details}{check_number} = sprintf( '%9s', $cheque_no );
			}
			elsif ( $transformed_rout_num eq '071915580' ) {
				$rule_set->{check_details}{routing_number} = $transformed_rout_num;
				$rule_set->{check_details}{account_number} =
					sprintf( '%7s', $jobbag->{check_details}{account_number} );
				$rule_set->{check_details}{check_number} = sprintf( '%9s', $cheque_no );
			}
			elsif ( $transformed_rout_num eq '125107888' ) {
				$rule_set->{check_details}{routing_number} = $transformed_rout_num;
				$rule_set->{check_details}{account_number} =
					sprintf( '%10s', $jobbag->{check_details}{account_number} );
				$rule_set->{check_details}{check_number} = sprintf( '%10s', $cheque_no );
			}
			else {
				$rule_set->{check_details}{routing_number} = $transformed_rout_num;
				$rule_set->{check_details}{account_number} = $jobbag->{check_details}{account_number};
				$rule_set->{check_details}{check_number}   = $cheque_no;
			}
		}

		$rule_set->{check_details}{name}            = $raw_set->{Cdtr}{Nm};
		$rule_set->{check_details}{building_number} = $raw_set->{Cdtr}{PstlAdr}{BldgNb};
		$rule_set->{check_details}{street_name}     = $raw_set->{Cdtr}{PstlAdr}{StrtNm};
		$rule_set->{check_details}{city}            = $raw_set->{Cdtr}{PstlAdr}{TwnNm};
		$rule_set->{check_details}{state}           = $raw_set->{Cdtr}{PstlAdr}{CtrySubDvsn};
		$rule_set->{check_details}{zip_code}        = $raw_set->{Cdtr}{PstlAdr}{PstCd};

		# when there are multiple AdrLines nodes in the XML it comes across as an array
		# force this to be an array when there's a single AdrLine so we can use the same code in either case
		if ( defined $raw_set->{Cdtr}{PstlAdr}{AdrLine} and ref $raw_set->{Cdtr}{PstlAdr}{AdrLine} ne 'ARRAY' ) {
			$raw_set->{Cdtr}{PstlAdr}{AdrLine} = [ $raw_set->{Cdtr}{PstlAdr}{AdrLine} ];
		}
		foreach my $adr_line ( @{ $raw_set->{Cdtr}{PstlAdr}{AdrLine} } ) {
			push @{ $rule_set->{check_details}{adr_lines} }, "$adr_line";
		}

		if ( '' eq $rule_set->{check_details}{street_name} ) {
			if ( @{ $rule_set->{check_details}{adr_lines} }[0] ) {
				$rule_set->{check_details}{street_name} = @{ $rule_set->{check_details}{adr_lines} }[0];
			}
		}

		# now assign the cached enCompass2 data to process in this current iteration
		# there won't be any record present in the cache if the account number is not present in enCompass2
		if ( $jobbag->{_encompass_data}{ $jobbag->{check_details}{account_number} } ) {
			$enCompass2_details = $jobbag->{_encompass_data}{ $jobbag->{check_details}{account_number} };
		}
		else {
			# data for account number is not found
			# hence reset $enCompass2_details
			$enCompass2_details = undef;
		}

		$jobbag->{pmt_inf}{group}{status} = 'ACCP' if !defined $jobbag->{pmt_inf}{group}{status};

		my $signature_graphic_details;
		if ( $enCompass2_details && !$jobbag->{acct_error}->{ $jobbag->{check_details}{account_number} } ) {
			$signature_graphic_details = _get_signature_graphic(
				$jobbag,
				$rule_set->{check_details}{check_amount},
				$enCompass2_details->{check_amount_rule}
			);

			$rule_set->{check_details}{check_signature_graphic} =
				$signature_graphic_details->{check_signature_graphic};
			$rule_set->{check_details}{check_signature_graphic_dir} =
				$signature_graphic_details->{check_signature_graphic_dir};
		}

		# WR 576
		# fill the rule_set with address2/3/4, void_after, table_type from encompass2
		$rule_set->{check_details}{bank_address2} = $enCompass2_details->{bank_address2} // '';
		$rule_set->{check_details}{bank_address3} = $enCompass2_details->{bank_address3} // '';
		$rule_set->{check_details}{bank_address4} = $enCompass2_details->{bank_address4} // '';
		$rule_set->{check_details}{void_after}    = $enCompass2_details->{void_after}    // '';
		$rule_set->{check_details}{table_type}    = $enCompass2_details->{table_type}    // '';

		$rule_set->{file_information}{file_name}        = @{ $jobbag->{__run_params}{data_files} }[0];
		$rule_set->{file_information}{company_name}     = $enCompass2_details->{company_name} // '';
		$rule_set->{file_information}{number_of_checks} = $jobbag->{file_information}{number_of_checks};
		$rule_set->{file_information}{check_total}      = $jobbag->{file_information}{check_total};

		# WR565
		$rule_set->{file_information}{party_id} = $jobbag->{file_information}{party_id};
		$rule_set->{file_information}{tran_id}  = $rule_set->{check_details}{pmt_id};      #from line 270

		my $special_handling_code;
		if (    exists $raw_set->{ChqInstr}
			and ref $raw_set->{ChqInstr}
			and not exists $raw_set->{ChqInstr}{DlvryMtd} )
		{
			$special_handling_code = undef;
		}
		elsif ( exists $raw_set->{ChqInstr}
			and ref $raw_set->{ChqInstr}
			and exists $raw_set->{ChqInstr}{DlvryMtd}
			and ref $raw_set->{ChqInstr}{DlvryMtd}
			and not exists $raw_set->{ChqInstr}{DlvryMtd}{Prtry} )
		{
			$special_handling_code = undef;
		}
		elsif ( exists $raw_set->{ChqInstr}
			and ref $raw_set->{ChqInstr}
			and exists $raw_set->{ChqInstr}{DlvryMtd}
			and ref $raw_set->{ChqInstr}{DlvryMtd}
			and exists $raw_set->{ChqInstr}{DlvryMtd}{Prtry} )
		{
			$special_handling_code = $raw_set->{ChqInstr}{DlvryMtd}{Prtry};
		}

		# populate the courier information only if the special handling code exists
		# .. and .. if there is a data in enCompass2 for this account number
		if ( $special_handling_code && $enCompass2_details ) {
			$rule_set->{file_information}{courier_account_number}  = $enCompass2_details->{courier_account_no};
			$rule_set->{file_information}{courier_bill_to_name}    = $enCompass2_details->{bill_to_name};
			$rule_set->{file_information}{courier_bill_to_street}  = $enCompass2_details->{bill_to_street};
			$rule_set->{file_information}{courier_bill_to_city}    = $enCompass2_details->{bill_to_city};
			$rule_set->{file_information}{courier_bill_to_state}   = $enCompass2_details->{bill_to_state};
			$rule_set->{file_information}{courier_bill_to_zipcode} = $enCompass2_details->{bill_to_zipcode};
			$rule_set->{file_information}{courier_option}          = $enCompass2_details->{courier_option};
		}

		# WR565
		if ( $enCompass2_details->{pdf_image_flag} ) {
			$rule_set->{file_information}{pdf_image_flag} = $enCompass2_details->{pdf_image_flag};
		}

		$rule_set->{payer_details}{transaction_id}                  = $jobbag->{payer_details}{transaction_id};
		$rule_set->{payer_details}{name}                            = $jobbag->{payer_details}{name};
		$rule_set->{payer_details}{building_number}                 = $jobbag->{payer_details}{building_number};
		$rule_set->{payer_details}{street_name}                     = $jobbag->{payer_details}{street_name};
		$rule_set->{payer_details}{city}                            = $jobbag->{payer_details}{city};
		$rule_set->{payer_details}{state}                           = $jobbag->{payer_details}{state};
		$rule_set->{payer_details}{zip_code}                        = $jobbag->{payer_details}{zip_code};
		$rule_set->{payer_details}{vendor_id}                       = $raw_set->{Cdtr}{Id}{OrgId}{Othr}{Id};
		$rule_set->{payer_details}{special_handling}                = $special_handling_code;
		$rule_set->{payer_details}{special_handling_name}           = $enCompass2_details->{name} // '';
		$rule_set->{payer_details}{special_handling_attention}      = $enCompass2_details->{attn} // '';
		$rule_set->{payer_details}{special_handling_street_address} = $enCompass2_details->{street_addr} // '';
		$rule_set->{payer_details}{special_handling_city}           = $enCompass2_details->{city} // '';
		$rule_set->{payer_details}{special_handling_state}          = $enCompass2_details->{state} // '';
		$rule_set->{payer_details}{special_handling_zip_code}       = $enCompass2_details->{zip_code} // '';
		$rule_set->{payer_details}{email_username}                  = $enCompass2_details->{email_username} // '';
		$rule_set->{payer_details}{email_domain}                    = $enCompass2_details->{email_domain} // '';
		$rule_set->{payer_details}{email_extension}                 = $enCompass2_details->{email_extension} // '';
		$rule_set->{payer_details}{zipfile_password}                = $enCompass2_details->{zipfile_password} // '';

	}    # end of CdtTrfTxInf

	return 1;
}

sub _get_signature_graphic {
	my ( $jobbag, $check_amount, $check_amount_rule ) = @_;

	my $account_number = $jobbag->{check_details}{account_number};

	my $check_signature_graphic;
	if ( $check_amount_rule =~ /Not Applicable/i || $check_amount < $check_amount_rule ) {
		$check_signature_graphic = "Signature_$account_number.pdf";
	}
	elsif ( $check_amount >= $check_amount_rule ) {
		$check_signature_graphic = "Signature_${account_number}_2.pdf";
	}
	else {
		Utils::JEF_Exception::terminate(
"Cannot determine the check signature graphic for account '$account_number', check amount '$check_amount' and check amount rule '$check_amount_rule'."
		);
	}

	my $check_signature_graphic_dir =
		CcsCommon::get_setting( 'graphics', 'po_path' ) . "\\$jobbag->{__config}{job}{client_name}";

# graphics directory for account specific signature
# no need for the full path here, just the client name since that will be the name of the folder used in the check complex segement
	my %signature_graphic_details;
	if ( -e "$check_signature_graphic_dir\\$check_signature_graphic" ) {
		$signature_graphic_details{check_signature_graphic}     = $check_signature_graphic;
		$signature_graphic_details{check_signature_graphic_dir} = $jobbag->{__config}{job}{client_name};
	}
	else {
		my $subject = "[$account_number] signature not found";
		my $body = "[$account_number] signature graphic not found in [$check_signature_graphic]. Please investigate!";
		my $to   = 'USCCSCommAM@computershare.com,NACTGOperations&Support@computershare.com';
		my $from = 'No-Reply-US@no-reply.com';

		my %mail = (
			to           => [ split( ',', $to ) ],
			from         => $from,
			fromdispname => $from,
			subject      => $subject,
			body         => [$body],
		);

		CcsSmtp::SendMail( \%mail );

		Utils::JEF_Exception::terminate(
			"Directory\\file $check_signature_graphic_dir\\$check_signature_graphic not found: $!");
	}

	return \%signature_graphic_details;
}

####-------------- New implementation using DAL
sub _get_encompass_details {
	my ( $jobbag, $account_number ) = @_;

	my $dal = DBHelper::create_encompass_connection(
		{
			db_retries    => $jobbag->{extra_options}{db_retries}    // 1,
			db_retry_time => $jobbag->{extra_options}{db_retry_time} // 1,
			dsnDetails    => \%dsnDetails,
		}
	);

	my $final_result = DBHelper::get_encompass_config( $dal, $account_number );
	my %enCompass2_details;

	foreach my $idx ( keys( %{ $final_result->{client_settings} } ) ) {
		my $record = $final_result->{client_settings}->{$idx};

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
			'pdf_image_flag'     => 'pdf_image_flag',                  # W565
			                                                           # WR 576 add address2/3/4, void_after, table_type
			'bank_address2'      => 'bank_address2',
			'bank_address3'      => 'bank_address3',
			'bank_address4'      => 'bank_address4',
			'void_after'         => 'void_after',
			'table_type'         => 'table_type',
		);

		foreach my $field ( %{$record} ) {
			if ( $field =~ /check_amount_rule/i ) {
				# remove the $ and , from the amount that's in enCompass2 so it can be compared
				# with the dollar amount of the check
				( $enCompass2_details{check_amount_rule} = $record->{$field} ) =~ s/\$|\,//g;
			}
			else {
				if ( $enCompass2_mapping{$field} ) {
					$enCompass2_details{$field} = $record->{$field};
				}
			}
		}
	}

	return \%enCompass2_details;
}

# read *all* the account numbers from input XML file
# this is used to reduce trips to DB
sub _process_DbtrAcct {
	my ( $twig, $acct ) = @_;

	my $acct_no = $acct->first_child('Id')->text;

	push( @acct_nos, $acct_no );
	$twig->purge;    #discard anything we've already seen.

	return;
}

sub _read_acct_numbers {
	my ( $this, $jobbag ) = @_;
	my $file = $jobbag->{'__data'}{file_name};
	my $twig = XML::Twig->new( twig_handlers => { 'DbtrAcct' => \&_process_DbtrAcct } );
	$twig->parsefile($file);

	return;
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

# This subroutine does form the PAIN002 object
# that will be used in PostProcessor to create a PAIN002 file
sub _prep_pain002_object {
	my ($data) = @_;

	my $jobbag          = $data->{jobbag};
	my $rule_set        = $data->{ruleset};
	my $raw_set         = $data->{rawset};
	my $status          = $data->{status};
	my $reason_code     = $data->{reason_code};
	my $business_reason = $data->{business_reason};

	$jobbag->{pmt_inf}{group}{status}          = $status;
	$jobbag->{pmt_inf}{group}{reason_code}     = $reason_code;
	$jobbag->{pmt_inf}{group}{business_reason} = $business_reason;
	$jobbag->{pmt_inf}{group}{date_time}       = $jobbag->{convert_timestamp};
	$jobbag->{pmt_inf}{group}{transaction_id}  = $jobbag->{payer_details}{transaction_id};
	$jobbag->{pmt_inf}{group}{payment_id}      = $rule_set->{check_details}{pmt_id};

	if ( !defined $jobbag->{'file_issues'}{group}{status} ) {
		push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
			{
			payment_id      => $rule_set->{check_details}{pmt_id},
			status          => $status,
			reason_code     => $reason_code,
			check_amount    => $rule_set->{check_details}{check_amount},
			currency        => $rule_set->{check_details}{check_currency},
			transaction_id  => $jobbag->{payer_details}{transaction_id},
			business_reason => $business_reason,
			check_number    => $rule_set->{check_details}{check_number} || $raw_set->{ChqInstr}{ChqNb},
			account_number  => $jobbag->{check_details}{account_number},
			routing_number  => $data->{transformed_rout_num},
			ccs_endtoend_id => $rule_set->{check_details}{ccs_endtoend_id},
			check_date      => $rule_set->{check_details}{check_date},
			};

		# increment overall count
		$jobbag->{reject}++;
		$jobbag->{reject_chk_amount} =
			sprintf( "%.2f", ( $jobbag->{reject_chk_amount} || 0 ) + $rule_set->{check_details}{check_amount} );

		#increment transaction-level count and accumulated check amounts
		$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
		$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
			( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) +
				$rule_set->{check_details}{check_amount} );
	}

	return;
}

1;
