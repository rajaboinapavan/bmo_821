package DupCheckPreProcessor;

use 5.010;

use strict;
use warnings;

use base qw(JobEngine_PreProcessor);

use lib_CCS(
	local =>
		[ 'Modules', 'Modules/Processors', 'Modules/BusinessRules', 'Modules/Renders', 'Modules/Utils', '../Common', ],
	others => [
		$ENV{CCS_RESOURCE} . '/Global/Std',
		$ENV{CCS_RESOURCE} . '/Regional',
		$ENV{CCS_RESOURCE} . '/Regional/<lib_ccs_region>/Finalist/5.10',
		$ENV{CCS_RESOURCE} . '/Regional/NA/Library',

	],
);

use Data::Dumper;

use NA::Std::Paths;
use GPD;
use ConfigReader;
use CcsDb;

use ISO_Utils;
use DupCheck_Utils;

################################################################################

# JEF-----------------------------------------------------------------

sub run {
	my ( $this, $jobbag ) = @_;

	my $dup_cnt             = 0;
	my $temp_run_no         = '000000000';
	my $dupcheck_reportfile = '145BM0100_Duplicate_Check_' . $temp_run_no . '.csv';
	my $files_with_dup      = '';
	my %duplicates;
	my %transaction_obj;

	foreach my $file_name ( @{ $jobbag->{__run_params}{data_files} } ) {
		# if there's a file level issue from ConverterPreProcessor, no need to process duplicates
		if ( defined $jobbag->{'file_issues'}{group}{status} and 'RJCT' eq $jobbag->{'file_issues'}{group}{status} ) {
			next;
		}

		if ( defined $jobbag->{'iso_xml_file'} && -e "$jobbag->{__run_params}{data_dir}\\$jobbag->{'iso_xml_file'}" ) {
			$file_name = $jobbag->{'iso_xml_file'};
		}
		else {
			Utils::JEF_Exception::terminate(
				"\nFile processed by ConverterPreProcessor not found $jobbag->{'iso_xml_file'} : $!");
		}

		my $f_name = $jobbag->{'iso_xml_file'};

		# open data file and read into hash
		my $data_dir = JEF::get_params( $jobbag, 'data_dir' );
		my $file = DataFile::XML2->open( "$data_dir/$jobbag->{'iso_xml_file'}", 1 );    # pull in the entire record

		while ( my $rec = $file->next() ) {

			# pass the $rec to the sub to simplify traversing the hashes
			my $rec = ISO_Utils::fake_force_array($rec);

			foreach my $pmt_inf ( @{ $rec->{CstmrCdtTrfInitn}[0]{PmtInf} } ) {
				my $transit_number;
				if (    exists $pmt_inf->{DbtrAgt}
					and exists $pmt_inf->{DbtrAgt}[0]
					and ref $pmt_inf->{DbtrAgt}[0]
					and exists $pmt_inf->{DbtrAgt}[0]{FinInstnId}
					and exists $pmt_inf->{DbtrAgt}[0]{FinInstnId}[0]
					and ref $pmt_inf->{DbtrAgt}[0]{FinInstnId}[0]
					and exists $pmt_inf->{DbtrAgt}[0]{FinInstnId}[0]{ClrSysMmbId}
					and exists $pmt_inf->{DbtrAgt}[0]{FinInstnId}[0]{ClrSysMmbId}[0]
					and ref $pmt_inf->{DbtrAgt}[0]{FinInstnId}[0]{ClrSysMmbId}[0]
					and exists $pmt_inf->{DbtrAgt}[0]{FinInstnId}[0]{ClrSysMmbId}[0]{MmbId}
					and not ref $pmt_inf->{DbtrAgt}[0]{FinInstnId}[0]{ClrSysMmbId}[0]{MmbId}[0] )
				{
					$transit_number = $pmt_inf->{DbtrAgt}[0]{FinInstnId}[0]{ClrSysMmbId}[0]{MmbId}[0];
				}
				else {
					$transit_number = undef;
				}

				my $transaction_id     = $pmt_inf->{PmtInfId}[0];
				my $pmt_inf_check_date = $pmt_inf->{ReqdExctnDt}[0];

				foreach my $tx_inf ( @{ $pmt_inf->{CdtTrfTxInf} } ) {
					my $payment_id      = $tx_inf->{PmtId}[0]{EndToEndId}[0];
					my $ccs_endtoend_id = $tx_inf->{PmtId}[0]{CCS_EndToEndID}[0];
					my $currency        = $tx_inf->{Amt}[0]{InstdAmt}[0]{Ccy}[0];
					my $payee           = $tx_inf->{Cdtr}[0]{Nm}[0];
					my $check_amount    = sprintf( "%.2f", ( $tx_inf->{Amt}[0]{InstdAmt}[0]{content}[0] || 0 ) );
					my $check_date      = $pmt_inf_check_date;

					my $acct_no;
					my $check_no;

					my $rjct_flag  = 0;
					my $dupe_found = 0;

					my $an;
					if (    exists $pmt_inf->{DbtrAcct}
						and exists $pmt_inf->{DbtrAcct}[0]
						and ref $pmt_inf->{DbtrAcct}[0]
						and exists $pmt_inf->{DbtrAcct}[0]{Id}
						and exists $pmt_inf->{DbtrAcct}[0]{Id}[0]
						and ref $pmt_inf->{DbtrAcct}[0]{Id}[0]
						and exists $pmt_inf->{DbtrAcct}[0]{Id}[0]{Othr}
						and exists $pmt_inf->{DbtrAcct}[0]{Id}[0]{Othr}[0]
						and ref $pmt_inf->{DbtrAcct}[0]{Id}[0]{Othr}[0]
						and exists $pmt_inf->{DbtrAcct}[0]{Id}[0]{Othr}[0]{Id}
						and not ref $pmt_inf->{DbtrAcct}[0]{Id}[0]{Othr}[0]{Id}[0] )
					{
						$an = $pmt_inf->{DbtrAcct}[0]{Id}[0]{Othr}[0]{Id}[0];
					}
					else {
						$an = undef;
					}

					my $cheque_no;
					if (    exists $tx_inf->{ChqInstr}
						and exists $tx_inf->{ChqInstr}[0]
						and ref $tx_inf->{ChqInstr}[0]
						and exists $tx_inf->{ChqInstr}[0]{ChqNb}
						and exists $tx_inf->{ChqInstr}[0]{ChqNb}[0]
						and not ref $tx_inf->{ChqInstr}[0]{ChqNb}[0] )
					{
						$cheque_no = $tx_inf->{ChqInstr}[0]{ChqNb}[0];
					}
					else {
						$cheque_no = undef;
					}

					if (   defined $transit_number
						&& $transit_number ne ''
						&& defined $an
						&& $an ne ''
						&& defined $cheque_no
						&& $cheque_no ne '' )
					{
						$f_name =~ s/\.xml$//g;    # for use client data file name in emails, not PO XML
						$cheque_no =~ s/^\s+|\s+$//g;
						$an =~ s/^\s+|\s+$//g;
						$transit_number =~ s/^\s+|\s+$//g;
						$payee =~ s/\,/ /g;

						my $status          = '';
						my $reason_code     = '';
						my $business_reason = '';

						# check for non-numeric characters in the check number
						if ( $cheque_no =~ /\D/ ) {
							$status          = 'RJCT';
							$reason_code     = 'FF09';
							$business_reason = 'Cheque Number is not numeric';

							push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
								{
								payment_id      => $payment_id,
								status          => $status,
								reason_code     => $reason_code,
								check_amount    => $check_amount,
								currency        => $currency,
								transaction_id  => $transaction_id,
								business_reason => $business_reason,
								check_number    => $cheque_no,
								account_number  => $an,
								routing_number  => $transit_number,
								ccs_endtoend_id => $ccs_endtoend_id,
								check_date      => $check_date,
								};

							# increment overall count
							$jobbag->{reject}++;
							$jobbag->{reject_chk_amount} =
								sprintf( "%.2f", ( $jobbag->{reject_chk_amount} || 0 ) + $check_amount );

							#increment transaction-level count and accumulated check amounts
							$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
							$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
								( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) + $check_amount );

							$jobbag->{reject_type}{transaction}++;

							$rjct_flag = 0;    #toggle it off

							next;
						}

						$transaction_obj{payment_id}      = $payment_id;
						$transaction_obj{status}          = $status;
						$transaction_obj{reason_code}     = $reason_code;
						$transaction_obj{check_amount}    = $check_amount;
						$transaction_obj{currency}        = $currency;
						$transaction_obj{transaction_id}  = $transaction_id;
						$transaction_obj{business_reason} = $business_reason;
						$transaction_obj{check_no}        = $cheque_no;
						$transaction_obj{payee}           = $payee;
						$transaction_obj{file_name}       = $jobbag->{'orig_xml_file'};
						$transaction_obj{transit_number}  = $transit_number;
						$transaction_obj{acct_no}         = $an;
						$transaction_obj{ccs_endtoend_id} = $ccs_endtoend_id;
						$transaction_obj{check_date}      = $check_date;
						$transaction_obj{package}         = 'DupCheckPreProcessor';

						my $enc_transit_number;
						my $db_status;
						( $db_status, undef, $enc_transit_number, undef ) =
							DupCheck_Utils::account_lookup( $jobbag, %transaction_obj );

						next if !defined $enc_transit_number;

						if ( $enc_transit_number eq '071915580' ) {
							$acct_no  = sprintf( '%7s', $an );
							$check_no = sprintf( '%9s', $cheque_no );
						}
						elsif ( $enc_transit_number eq '071025661' ) {
							$acct_no  = sprintf( '%10s', $an );
							$check_no = sprintf( '%9s',  $cheque_no );
						}
						elsif ( $enc_transit_number eq '071000288' ) {
							$acct_no  = sprintf( '%10s', $an );
							$check_no = sprintf( '%9s',  $cheque_no );
						}
						elsif ( $enc_transit_number eq '125107888' ) {
							$acct_no  = sprintf( '%10s', $an );
							$check_no = sprintf( '%10s', $cheque_no );
						}
						else {
							$acct_no  = $an;
							$check_no = $cheque_no;
						}

						$f_name =~ s/\.xml$//g;    # for use client data file name in emails, not PO XML
						$check_no =~ s/^\s+|\s+$//g;
						$acct_no =~ s/^\s+|\s+$//g;
						$enc_transit_number =~ s/^\s+|\s+$//g;
						$payee =~ s/\,/ /g;

						my $consolidated_key = $enc_transit_number . '_' . $acct_no . '_' . $check_no;
						push @{ $duplicates{$consolidated_key} }, $ccs_endtoend_id;

						# validate data file for duplicated checks
						if ( 'RJCT' eq $db_status or scalar @{ $duplicates{$consolidated_key} } > 1 ) {
							## db dups reject on first error, in-file dups let the first one pass
							$jobbag->{'Duplicate_checks'}{$ccs_endtoend_id} = 1;    # from the file

							print "\nDuplicate check found in data file $f_name\nCheck details:\n"
								. "Check number - $check_no\nCheck amount - $check_amount\nPayee - $payee\nFile - $f_name\n ";

							my $needs_header = 1;
							if ( -e $dupcheck_reportfile && -s $dupcheck_reportfile ) {
								$needs_header = 0;
							}
							# dup report csv for found in file
							open my $DUPFILE, '>>', $dupcheck_reportfile
								or Utils::JEF_Exception::terminate("\nFailed to open $dupcheck_reportfile : $!");

							if ($needs_header) {
								# headers
								print $DUPFILE "Check Number,Check Amount,Payee,Input File\n";
								# fields
								print $DUPFILE "$check_no,$check_amount,$payee,$jobbag->{'orig_xml_file'}\n";
							}
							else {
								# fields
								print $DUPFILE "$check_no,$check_amount,$payee,$jobbag->{'orig_xml_file'}\n";
							}
							close $DUPFILE;
							$dup_cnt++;
							$dupe_found = 1;

							if ($dup_cnt) {
								# attach the file to the jobbag. This will be used in ConverterPostProcessor.
								$jobbag->{'dupcheck_reportfile'} = $dupcheck_reportfile;

								print Dumper $jobbag->{'dupcheck_reportfile'};
							}

							if ( 'RJCT' ne $db_status ) {
								$status          = 'RJCT';
								$reason_code     = 'DUPL';
								$business_reason = 'Duplicate check found within the input file';

								push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
									{
									payment_id      => $payment_id,
									status          => $status,
									reason_code     => $reason_code,
									check_amount    => $check_amount,
									currency        => $currency,
									transaction_id  => $transaction_id,
									business_reason => $business_reason,
									check_number    => $check_no,
									account_number  => $acct_no,
									routing_number  => $enc_transit_number,
									ccs_endtoend_id => $ccs_endtoend_id,
									check_date      => $check_date,
									};

								# increment overall count
								$jobbag->{reject}++;
								$jobbag->{reject_chk_amount} =
									sprintf( "%.2f", ( $jobbag->{reject_chk_amount} || 0 ) + $check_amount );

								#increment transaction-level count and accumulated check amounts
								$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
								$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
									( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) + $check_amount );

								$jobbag->{reject_type}{transaction}++;

								$jobbag->{rejected}{$ccs_endtoend_id}++;
								print "Too many rejects..$ccs_endtoend_id: $jobbag->{rejected}{$ccs_endtoend_id}\n"
									if $jobbag->{rejected}{$ccs_endtoend_id} > 1;

							}
						}
					}
				}
			}
		}
	}

	print "End of DupCheckPreProcessor\n";
	return;
}

# JEF-----------------------------------------------------------------

1;
