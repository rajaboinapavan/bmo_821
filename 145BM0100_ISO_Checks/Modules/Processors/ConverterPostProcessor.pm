package ConverterPostProcessor;

use 5.010;

use strict;
use warnings;

use base qw(GenericProcessor);

use Data::Dumper;
use XML::Simple;
use Logger::Log;
use File::Basename;
use DateTime;
use File::Copy;
use Time::HiRes qw/gettimeofday/;
use Time::localtime;
use Getopt::Long qw(GetOptionsFromArray :config pass_through);

use lib "$ENV{CCS_RESOURCE}";
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
use ISO_Utils;
use CcsSmtp;

# use NA::Std::EmailXmlUtils;
# use ZipUtils qw(zipFiles);

################################################################################

# JEF-----------------------------------------------------------------

sub run {
	my ( $this, $jobbag ) = @_;

	$this->SUPER::run($jobbag);

	my ( $archive, $email1, $email2 );
	# get the archive path, email1 and email2 if they exist from the extra hash
	my @opts_array = @{ $jobbag->{__run_params}{extra} };
	for ( my $i = 0 ; $i < scalar @opts_array ; $i++ ) {
		if ( $opts_array[$i] =~ /--archive/ ) {
			$archive = $opts_array[ $i + 1 ];
		}
		elsif ( $opts_array[$i] =~ /--email1/ ) {
			$email1 = $opts_array[ $i + 1 ];
		}
		elsif ( $opts_array[$i] =~ /--email2/ ) {
			$email2 = $opts_array[ $i + 1 ];
		}
	}

	my $status;
	if ( defined $jobbag->{'file_issues'}{group}{status} and 'RJCT' eq $jobbag->{'file_issues'}{group}{status} ) {
		$status = 'RJCT';
	}
	elsif (( defined $jobbag->{reject} && $jobbag->{reject} > 0 )
		&& ( defined $jobbag->{accept} && $jobbag->{accept} > 0 ) )
	{
		$status = 'PART';
	}
	elsif ( defined $jobbag->{reject} && $jobbag->{reject} > 0 ) {
		$status = 'RJCT';
	}
	elsif ( defined $jobbag->{accept} && $jobbag->{accept} > 0 ) {
		$status = 'ACCP';
	}

	if ( defined $status && $status =~ /RJCT|PART|ACCP/ ) {
		ISO_Utils::write_Ack($jobbag);
	}
	if ( defined $status && $status =~ /RJCT|PART/ ) {
		my $data_file_dir = $jobbag->{__run_params}{data_dir};
		my $ack_file      = $jobbag->{'ack_file'};

		my $attachment = "$data_file_dir/$ack_file";

		# send email notification to BMO
		my $subject;
		my $msg;

		if ( $jobbag->{reject_type}{file} ) {
			$subject = "Check Printing Mail File Error: $jobbag->{'file_issues'}{group}{reason_code}";
			$msg =
"$jobbag->{'iso_xml_file'}\nThe file received by Computershare has encountered a file level error.\n\nPlease refer to the Acknowledgement File sent via sFTP in the ISO20022 PAIN.002.001.03 format for the respective Reason Reject Codes per File Level failure.This is an automated email.\n\nIf you are experiencing problems, or you are receiving this in error, please contact Computershare Communication Services and ask for the Client Account Manager.\n\nThank you\n";
		}
		elsif ( 0 == $jobbag->{reject_type}{file} && $jobbag->{reject_type}{transaction} ) {
			$subject = "Transaction Level Error(s) Detected";
			$msg =
"$jobbag->{'iso_xml_file'}\nThe file received by Computershare contains one or more errors at the Transaction ID level. Computershare will not process this/these transaction(s) for printing or archiving.\n\nPlease refer to the Acknowledgement File sent via sFTP in the ISO20022 PAIN.002.001.03 format for the respective Reason Reject Codes per Transaction Level failure. Only the first transaction level error found per transaction will be noted in the Acknowledgement file.\n\nThis is an automated email. If you are experiencing problems, or you are receiving this in error, please contact Computershare Communication Services and ask for the Client Account Manager.\n\nThank you\n";

		}

		my %mail = (
			to           => [$email1],
			from         => '!USCSBURProgramming@computershare.com',
			fromdispname => '!USCSBURProgramming@computershare.com',
			recipients   => [$email1],
			subject      => $subject,
			body         => [$msg],
			attachments  => [$attachment],
		);

		CcsSmtp::SendMail( \%mail );

	}

	my $area = CcsCommon::get_env();

	# send out the duplicate report now if it exists using Run no '000000000'
	if ( defined $jobbag->{'dupcheck_reportfile'} and -e $jobbag->{'dupcheck_reportfile'} ) {
		my $temp_run_no = '000000000';
		my $recipients =
			$jobbag->{__config}{environment_settings}{ lc($area) }{notifications}
			{duplicate_check_notification}{email_recipient};
		my $email_file_name =
			$jobbag->{__config}{environment_settings}{ lc($area) }{notifications}
			{duplicate_check_notification}{email_xml_file_name};
		my $subject = "145BM0100 Duplicate Check in Run $temp_run_no";
		my $email_body =
"A duplicate check was identified in the below input file(s).  Attached is a file that contains the details of the record that failed.  Please contact client to let them know that this check was quarantined, did not print, and the rest of the file continued processing and printing.\n";

		Utilities::generate_email(
			recipients      => $recipients,
			subject         => $subject,
			email_body      => $email_body,
			email_file_name => $email_file_name,
			attachments     => $jobbag->{'dupcheck_reportfile'},
		);

		# archive the file
		Utilities::motus(
			action      => 'copy',
			source      => $jobbag->{'dupcheck_reportfile'},
			target      => $archive,
			threshhold  => $jobbag->{extra_options}{threshhold},
			sleep       => $jobbag->{extra_options}{sleep},
			alert_every => $jobbag->{extra_options}{alert_every},
		);
	}

	# If no sets were rendered, the .po.xml file will not be in a complete state
	# and cannot go through Doc Comp
	# conduct clean up operations
	if ( !defined $jobbag->{total_rendered_sets} || $jobbag->{total_rendered_sets} < 1 ) {
		# dump the transactions that failed and why
		foreach my $rejected_trans ( @{ $jobbag->{proc_transactions}{reject} } ) {
			print Dumper $rejected_trans;
		}
		move( "$jobbag->{__run_params}{data_dir}\\$jobbag->{'iso_xml_file'}", $archive )
			or Utils::JEF_Exception::terminate(
			"No sets were rendered.\nFailed to move the ID xml file to the $archive: $!");
		move( "$jobbag->{'intermediary_po_xml'}", $archive )
			or Utils::JEF_Exception::terminate(
			"No sets were rendered.\nFailed to move the .po.xml file to the $archive: $!");
		move( "$jobbag->{__run_params}{data_dir}\\$jobbag->{'orig_xml_file'}", $archive )
			or Utils::JEF_Exception::terminate(
			"No sets were rendered.\nFailed to move the original xml file to the $archive: $!");
		# now die
		Utils::JEF_Exception::terminate("No sets were rendered.\nNotify the account manager.");
	}

	my $doc_comp_trigger_dir =
		  CcsCommon::get_setting( 'GENERAL', 'datain_folder' ) . '\\'
		. $jobbag->{__config}{job}{client_name} . '_'
		. $jobbag->{__config}{job}{client_code} . '\\'
		. $jobbag->{__config}{job}{job_code} . '\\'
		. 'In\\DocComp';

	# if an intermediary_po_xml name was assigned and it exists copy
	# it to the staging location for the next Aa autoproc job
	if ( $jobbag->{'intermediary_po_xml'} and -e $jobbag->{'intermediary_po_xml'} ) {

		if ( not -d $doc_comp_trigger_dir ) {
			if ( not mkdir( $doc_comp_trigger_dir, 0777 ) ) {
				Utils::JEF_Exception::terminate( $doc_comp_trigger_dir . ' does not exist and could not be created' );
			}
		}

		Utilities::motus(
			action      => 'copy',
			source      => $jobbag->{'intermediary_po_xml'},
			target      => $doc_comp_trigger_dir,
			threshhold  => $jobbag->{extra_options}{threshhold},
			sleep       => $jobbag->{extra_options}{sleep},
			alert_every => $jobbag->{extra_options}{alert_every},
		);

		Utilities::motus(
			action      => 'copy',
			source      => "$jobbag->{__run_params}{data_dir}\\$jobbag->{'iso_xml_file'}",
			target      => $doc_comp_trigger_dir,
			threshhold  => $jobbag->{extra_options}{threshhold},
			sleep       => $jobbag->{extra_options}{sleep},
			alert_every => $jobbag->{extra_options}{alert_every},
		);

		Utilities::motus(
			action      => 'copy',
			source      => "$jobbag->{__run_params}{data_dir}\\$jobbag->{'orig_xml_file'}",
			target      => $doc_comp_trigger_dir,
			threshhold  => $jobbag->{extra_options}{threshhold},
			sleep       => $jobbag->{extra_options}{sleep},
			alert_every => $jobbag->{extra_options}{alert_every},
		);

	}
	else {
		Utils::JEF_Exception::terminate("PO XML '$jobbag->{'intermediary_po_xml'}' does not exist");
	}

	# place the the Acknowledgement PAIN002 on the path defined by the ccssite.ini bmo_outbound_ftp if UAT
	# else put it on the path defined for production
	my $bmo_outbound_ftp;

	if ( $area !~ /production/i ) {
		$bmo_outbound_ftp = CcsCommon::get_setting( 'reports', 'bmo_outbound_ftp' );
	}
	else {
		$bmo_outbound_ftp =
			  CcsCommon::get_setting( 'GENERAL', 'datain_folder' ) . '\\'
			. $jobbag->{__config}{job}{client_name} . '_'
			. $jobbag->{__config}{job}{client_code} . '\\'
			. $jobbag->{__config}{job}{job_code} . '\\Out';
	}

	if ( $jobbag->{'ack_file'} and -e "$jobbag->{__run_params}{data_dir}\\$jobbag->{'ack_file'}" ) {
		Utilities::motus(
			action      => 'copy',
			source      => "$jobbag->{__run_params}{data_dir}\\$jobbag->{'ack_file'}",
			target      => $bmo_outbound_ftp,
			threshhold  => $jobbag->{extra_options}{threshhold},
			sleep       => $jobbag->{extra_options}{sleep},
			alert_every => $jobbag->{extra_options}{alert_every},
		);
	}

	# WR577 fill in the client reports using the data generated in the Converter
	my $filename = $jobbag->{'iso_xml_file'};
	$filename =~ s/\.ID\.XML/\.XML/i;
	$this->_check_register_report( $filename, $jobbag );
	$this->_exception_report( $filename, $jobbag );
	$this->_disbursement_report( $filename, $jobbag );
	$this->_zip_and_email_client_reports( $filename, $jobbag );

	return;

}

sub _timestamp {

	my @date_string = localtime();

	my $dayOfMonth = sprintf( '%02d', $date_string[0][3] );
	my $month      = sprintf( '%02d', $date_string[0][4] + 1 );
	my $year       = sprintf( '%02d', $date_string[0][5] + 1900 );
	my $second     = sprintf( '%02d', $date_string[0][0] );
	my $minute     = sprintf( '%02d', $date_string[0][1] );
	my $hour       = sprintf( '%02d', $date_string[0][2] );
	my $processdate = "${year}-${month}-${dayOfMonth}T${hour}:${minute}:${second}";

	return $processdate;
}

sub _disbursement_report {
	my ( $this, $filename, $jobbag ) = @_;

	my %processed_acctnum;

	print "Producing Disbursement Report\n";

	my ( $col, $row );
	$col = $row = 0;    #first row and first column: A1

	my $disbursement_fname = 'Dis_summ_BMO' . $filename . '_BMO_USD.xls';

	push @{ $jobbag->{client_report_list}{ $jobbag->{$filename}{zip_file} } }, { 'report' => $disbursement_fname, };

	# Create a new Excel workbook
	my $workbook = Spreadsheet::WriteExcel->new($disbursement_fname);
	$workbook->compatibility_mode();

	# Add a worksheet
	my $worksheet = $workbook->add_worksheet();

	# Add and define cell format for the header row
	my $format;
	$format = $workbook->add_format();    # Add a format
	$format->set_bold();
	$format->set_align('center');

	#Column A format
	my $colA_format = $workbook->add_format();
	$colA_format->set_align('left');

	#Column B format
	my $colB_format = $workbook->add_format();
	$colB_format->set_align('right');
	$colB_format->set_num_format('#,##0');

	#Column C format
	my $colC_format = $workbook->add_format();
	$colC_format->set_align('right');
	$colC_format->set_num_format('$#,##0.00');

	#Header
	foreach my $header_line (
		'Computershare',
		'Disbursement Summary Report',
		$jobbag->{ $jobbag->{$filename}{disbursement_summary} }{company_name},
		$jobbag->{ $jobbag->{$filename}{disbursement_summary} }{file_name},
		'Date: ' . $jobbag->{ $jobbag->{$filename}{disbursement_summary} }{check_date}
		)
	{
		$worksheet->write( $row, 1, $header_line, $format );
		$row++;
	}

	# Table
	$col = 0;
	$row++;
	$worksheet->set_column( 'A:C', 40 );
	# table header 1 - Input Totals
	foreach my $table_header_1 ( 'INPUT TOTALS', 'Count', 'Value' ) {
		if ( $table_header_1 !~ /INPUT TOTALS/ ) {
			$worksheet->write( $row, $col, $table_header_1, $colB_format );
		}
		else {
			$worksheet->write( $row, $col, $table_header_1, $colA_format );
		}
		$col++;
	}

	# row entries under Input totals
	$col = 0;
	$row++;
	$worksheet->write( $row, $col, '  CHECKS TO BE PRINTED', $colA_format );
	$col++;
	$worksheet->write( $row, $col, $jobbag->{ack_info}{GrpHdr}{num_transactions}, $colB_format );
	$col++;
	$worksheet->write( $row, $col, $jobbag->{ack_info}{GrpHdr}{control_sum}, $colC_format );

	$col = 0;
	$row++;
	$worksheet->write( $row, $col, '  TOTAL ISSUED', $colA_format );
	$col++;
	$worksheet->write( $row, $col, $jobbag->{accept}, $colB_format );
	$col++;
	$worksheet->write( $row, $col, $jobbag->{accept_chk_amount}, $colC_format );

	# table header 2 - Runs Totals
	$col = 0;
	$row += 2;
	foreach my $table_header_2 ( 'RUN TOTALS', 'Count', 'Value' ) {
		if ( $table_header_2 !~ /RUN TOTALS/ ) {
			$worksheet->write( $row, $col, $table_header_2, $colB_format );
		}
		else {
			$worksheet->write( $row, $col, $table_header_2, $colA_format );
		}
		$col++;
	}

	foreach my $formatted_acctno ( @{ $jobbag->{$filename}{acctno} } ) {

		if ( exists $processed_acctnum{$formatted_acctno} && $processed_acctnum{$formatted_acctno} ) {
			next;
		}
		else {
			$processed_acctnum{$formatted_acctno}++;

			$col = 0;
			$row++;
			# Checks Printed row
			$worksheet->write( $row, $col, '  CHECKS PRINTED -' . $formatted_acctno, $colA_format );
			$col++;

			if ( $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{accp}{count} ) {
				$worksheet->write( $row, $col, $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{accp}{count},
					$colB_format );
			}
			else {
				$worksheet->write( $row, $col, "0", $colB_format );
			}
			$col++;
			if ( $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{accp}{value} ) {
				$worksheet->write( $row, $col, $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{accp}{value},
					$colC_format );
			}
			else {
				$worksheet->write( $row, $col, "0", $colC_format );
			}

			# Checks rejected row
			$col = 0;
			$row++;
			$worksheet->write( $row, $col, '  CHECKS REJECTED -' . $formatted_acctno, $colA_format );
			$col++;

			if ( $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rejected}{count} ) {
				$worksheet->write( $row, $col,
					$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rejected}{count}, $colB_format );
			}
			else {
				$worksheet->write( $row, $col, "0", $colB_format );
			}
			$col++;

			if ( $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rejected}{value} ) {
				$worksheet->write( $row, $col,
					$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rejected}{value}, $colC_format );
			}
			else {
				$worksheet->write( $row, $col, "0", $colC_format );
			}
		}
	}

	$row += 2;
	$col = 0;

	# Total Row
	$worksheet->write( $row, $col, '  TOTAL (USD)', $colA_format );
	$col++;

	$worksheet->write( $row, $col, $jobbag->{ack_info}{GrpHdr}{num_transactions}, $colB_format );
	$col++;

	$worksheet->write( $row, $col, $jobbag->{ack_info}{GrpHdr}{control_sum}, $colC_format );

	$workbook->close();

	return 1;
}

sub _check_register_report {
	my ( $this, $file_name, $jobbag ) = @_;
	my ( $col, $row );
	my $workbook;
	my $format;

	print "\nGenerating Check Register report...\n";

	foreach my $chk_reg_file ( keys %{ $jobbag->{check_register_report_details} } ) {

		# get the formatted account number
		$chk_reg_file =~ /_(XXXX.*)\.xls$/;
		my $formatted_acctno = $1;

		$col = $row = 0;    #first row and first column: A1

		# Create a new Excel workbook
		$workbook = Spreadsheet::WriteExcel->new($chk_reg_file);
		$workbook->compatibility_mode();

		# Add a worksheet
		my $worksheet = $workbook->add_worksheet();

		# Add and define cell format for the header row
		$format = $workbook->add_format();    # Add a format
		$format->set_bold();
		$format->set_align('center');

		#Column A and C format
		my $colAC_format = $workbook->add_format();
		$colAC_format->set_align('left');

		#Column B format
		my $colB_format = $workbook->add_format();
		$colB_format->set_align('right');
		$colB_format->set_num_format('#,##0');

		#Column D format
		my $colD_format = $workbook->add_format();
		$colD_format->set_align('right');
		$colD_format->set_num_format('$#,##0.00');

		#title
		foreach my $header_line (
			'Computershare',
			'Check Register Report',
			$jobbag->{ $jobbag->{$file_name}{formatted_acctno}{$formatted_acctno}{checkreg_file} }{company_name},
			$file_name,
			'DATE: '
			. $jobbag->{ $jobbag->{$file_name}{formatted_acctno}{$formatted_acctno}{checkreg_file} }{check_date},
			'ACCOUNT NUMBER: ' . $jobbag->{$chk_reg_file}{account_number},
			)
		{
			$worksheet->write( $row, 2, $header_line, $format );
			$row++;
		}

		# Table
		$row++;
		$worksheet->set_column( 'A:A', 18 );
		$worksheet->set_column( 'B:B', 12 );
		$worksheet->set_column( 'C:C', 50 );
		$worksheet->set_column( 'D:D', 24 );

		# table header 1
		foreach my $table_header_1 ( 'CHECK NUMBER', 'DATE', 'PAYEE NAME', 'CHECK AMOUNT' ) {
			if ( $table_header_1 =~ /CHECK NUMBER|PAYEE NAME/ ) {
				$worksheet->write( $row, $col, $table_header_1, $colAC_format );
			}
			else {
				$worksheet->write( $row, $col, $table_header_1, $colB_format );
			}
			$col++;
		}

		# row entries
		for my $row_value ( @{ $jobbag->{check_register_report_details}{$chk_reg_file} } ) {
			$col = 0;
			$row++;
			$worksheet->write( $row, $col, $row_value->{check_number}, $colAC_format );
			$col++;
			$worksheet->write( $row, $col, $row_value->{check_date}, $colB_format );
			$col++;
			$worksheet->write( $row, $col, $row_value->{payee_line_1}, $colAC_format );
			$col++;
			$worksheet->write( $row, $col, $row_value->{check_amount}, $colD_format );
		}

		$col = 0;
		$row += 2;
		# Total row
		for my $total_cell ( 'COUNT', $jobbag->{$chk_reg_file}{number_of_checks}, 'TOTAL' ) {
			$worksheet->write( $row, $col, $total_cell, $colB_format );
			$col++;
		}
		$worksheet->write( $row, $col, $jobbag->{$chk_reg_file}{check_total}, $colD_format );

		$workbook->close();
	}
	return 1;
}

sub _exception_report {
	my ( $this, $filename, $jobbag ) = @_;

	print "\nGenerating Exception report...\n";

	my ( $col, $row );
	$col = $row = 0;    #first row and first column: A1

	my $exception_fname = 'Exception_' . $filename . '.xls';

	# Create a new Excel workbook
	my $workbook = Spreadsheet::WriteExcel->new($exception_fname);
	$workbook->compatibility_mode();

	# Add a worksheet
	my $worksheet = $workbook->add_worksheet();

	# Add and define cell format for the header row
	my $format;
	$format = $workbook->add_format();
	$format->set_bold();
	$format->set_align('center');

	#Column format
	my $col_format = $workbook->add_format();
	$col_format->set_align('left');

	#Header
	foreach my $header_line (
		'Computershare',
		'Exception Summary Report',
		$jobbag->{ $jobbag->{$filename}{exception_file} }{company_name},
		$filename, 'Date: ' . $jobbag->{ $jobbag->{$filename}{exception_file} }{run_date}
		)
	{
		$worksheet->write( $row, 1, $header_line, $format );
		$row++;
	}

	# Table
	$col = 0;
	$row++;
	$worksheet->set_column( 'A:C', 30 );

	# table header
	foreach my $table_header ( 'ACCOUNT', 'CHECK NUM', 'EXCEPTION' ) {
		$worksheet->write( $row, $col, $table_header, $col_format );
		$col++;
	}

	if ( exists $jobbag->{ $jobbag->{$filename}{exception_file} }{details} ) {

		foreach my $rjct ( @{ $jobbag->{ $jobbag->{$filename}{exception_file} }{details} } ) {
			$row++;
			$col = 0;
			$worksheet->write( $row, $col, $rjct->{acct_number}, $col_format );
			$col++;
			$worksheet->write( $row, $col, $rjct->{check_number}, $col_format );
			$col++;
			$worksheet->write( $row, $col, $rjct->{business_reason}, $col_format );

		}
	}
	else {
		$row++;
		$col = 0;
		$worksheet->write( $row, $col, "No exceptions were found", $col_format );
		$col += 2;
		$worksheet->write( $row, $col, "No exceptions were found", $col_format );
	}

	$workbook->close();

	return 1;
}

sub _zip_and_email_client_reports {
	my ( $this, $filename, $jobbag ) = @_;
	my @report_array;
	my $cmd;

	my $exe = NA::Std::Utils::get7zipExecutablePath();

	my $doc_comp_trigger_dir =
		  CcsCommon::get_setting( 'GENERAL', 'datain_folder' ) . '\\'
		. $jobbag->{__config}{job}{client_name} . '_'
		. $jobbag->{__config}{job}{client_code} . '\\'
		. $jobbag->{__config}{job}{job_code} . '\\'
		. 'In\\DocComp';

	foreach my $zip ( keys %{ $jobbag->{client_report_list} } ) {

		# zip the reports
		foreach my $report_file ( values %{ $jobbag->{client_report_list} } ) {
			foreach my $element ( @{$report_file} ) {
				my ( $type, $report ) = each %{$element};
				push @report_array, $report if -e $report;
			}
		}

		if ( $jobbag->{ $jobbag->{$filename}{zip_file} }{zip_password} ) {
			$cmd = "$exe a $zip -p$jobbag->{ $jobbag->{$filename}{zip_file} }{zip_password} @report_array";
		}
		else {
			print "Executing without password\n";
			$cmd = "$exe a $zip @report_array";
		}
		print "EXECUTING: $exe to zip the client reports into $zip\n";
		`$cmd`;
		if ($?) {
			Utils::JEF_Exception::terminate("Failed to add the client reports to the zip file, $zip. Error: $?");
		}
		else {
			while (@report_array) {
				unlink( pop @report_array );
			}
		}

		my %mail = (
			to           => [ split( ',', $jobbag->{ $jobbag->{$filename}{zip_file} }{email_address} ) ],
			from         => 'NoReply-US@BMO.com',
			fromdispname => 'NoReply-US@BMO.com',
			recipients  => [ $jobbag->{ $jobbag->{$filename}{zip_file} }{email_address} ],
			subject     => 'BMO ISO Check Reports',
			body        => ['See the attached report zip file'],
			attachments => defined $zip ? [ split( ',', $zip ) ] : []
		);

		CcsSmtp::SendMail( \%mail );

		# copy the zipped client reports to the doc comp trigger directory for archival with the other files
		Utilities::motus(
			action      => 'copy',
			source      => "$zip",
			target      => $doc_comp_trigger_dir,
			threshhold  => $jobbag->{extra_options}{threshhold},
			sleep       => $jobbag->{extra_options}{sleep},
			alert_every => $jobbag->{extra_options}{alert_every},
		);

	}

	return 1;

}

1;
