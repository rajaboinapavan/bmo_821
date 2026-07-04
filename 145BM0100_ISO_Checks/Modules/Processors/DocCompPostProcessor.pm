package DocCompPostProcessor;

use 5.010;

use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray :config pass_through);

use lib "$ENV{CCS_RESOURCE}";

use lib_CCS(
	GPD       => '3.00',
	JEF       => '1.00',
	JobEngine => '1.00',
);
use base qw(JobEngine_PostProcessor);

use lib $ENV{CCS_RESOURCE} . '/Global/Std';
use DataFile::XML2;
use Logger::Log;

use lib $ENV{'CCS_RESOURCE'} . '/Global/Perl/5.10/site/lib';
use File::Copy;
use Data::Dumper;
use UtilsGpdReaders;

use lib 'Common';
use Utilities;

use lib "Modules/Utils";
use ISO_Utils;

################################################################################

# JEF-----------------------------------------------------------------

sub run {
	my ( $this, $jobbag ) = @_;

	$this->SUPER::run($jobbag);

	################################################################################
	## Be sure to wrap anything not neccessary during sampling in a conditional
	##
	## 		if not $jobbag->{__run_params}{options}{po_sample_mode}
	##
	## If you don't, you'll start blowing out processing times! NOT GOOD!
	################################################################################

	###
	# Generate sample PDFs
	###
	if ( $jobbag->{extra_options}{pdf_samples} ) {

		my $cmd = "$ENV{CCS_RESOURCE}\\Global\\Scripts\\g2p.cmd --micr_gauge --sg 145BM0100_*.gpd";
		system($cmd);
		if ($?) {
			Utils::JEF_Exception::terminate("Something unexpected happened with $cmd\n$?");
		}
	}

	if ( !$jobbag->{__run_params}{options}{po_sample_mode} ) {
		$this->_create_addressfile($jobbag);
		$this->_create_reports($jobbag);

		#from autoproc extra argument
		my $datain_path = $jobbag->{extra_options}{input_folder}
			|| Utils::JEF_Exception::terminate('Extra argument, input folder must be defined in Aardvark autoproc');
		$this->_include_client_reports( $datain_path, $jobbag );
		$this->_include_origxmlfile( $datain_path, $jobbag );

	}

	return 1;
}

sub _create_addressfile {
	my ( $this, $jobbag ) = @_;

	foreach my $gpd ( glob('145BM0100_*.gpd') ) {
		my $noext_gpd = ( split( /\./, $gpd ) )[0];

		if ( $gpd =~ /UPS|FEDEX/i ) {
			if ( !$jobbag->{__run_params}{options}{po_sample_mode} ) {
				#Address label file creation after sorting the bulk gpds
				if ( $gpd =~ /_UPS_Lg/i ) {
					$this->_create_UPS_addressfile( $gpd, $jobbag );
				}
				elsif ( $gpd =~ /_UPSBulk_/i ) {
					$this->_create_UPSBulk_addressfile( $gpd, $jobbag );
				}
				elsif ( $gpd =~ /_FEDEX_/i ) {
					$this->_create_FedEx_addressfile( $gpd, $jobbag );
				}
				elsif ( $gpd =~ /_FEDEXBulk_/i ) {
					$this->_create_FedExBulk_addressfile( $gpd, $jobbag );
				}
			}
		}

		#WR565 - Create pdf if pdf_image check box is ticked in enCompasse
		$this->_create_pdf_and_zip( $gpd, $jobbag );
	}
	return 1;
}

sub _create_UPS_addressfile {
	my ( $this, $gpd_name, $jobbag ) = @_;

	my $sets_info = UtilsGpdReaders::get_sets_info(
		filename      => $gpd_name,
		incl_tags     => 1,
		set_tags_spec => ['^addresslabel'],
	) or Utils::JEF_Exception::terminate("\nNo addresslabel set tag found at $gpd_name.");

	my $address_label_fname = $gpd_name . '.csv';
	$address_label_fname =~ s/_|\.gpd//gi;

	open my $ADDRFILE, '>>', $address_label_fname
		or Utils::JEF_Exception::terminate("\nFailed to open $address_label_fname : $!");

	foreach my $tag_num ( 1 .. @{ $sets_info->{tags} } - 1 ) {
		# put the header row before the first set
		if ( $tag_num == 1 ) {
			print $ADDRFILE 'CustomerID,'
				. 'CompanyName,'
				. 'Attention,'
				. 'Address1,'
				. 'Address2,'
				. 'Address3,' . 'City,'
				. 'State,'
				. 'Zipcode,'
				. 'Email,'
				. 'Phone,'
				. 'Reference1,'
				. 'Reference2,'
				. 'Weight,'
				. 'Service,'
				. 'PackageType,'
				. 'BillTransportationTo,'
				. 'bill_to_name,'
				. 'bill_to_address,'
				. 'bill_to_country,'
				. 'bill_to_zip,'
				. 'bill_to_city,'
				. 'bill_to_state,'
				. 'bill_to_account';
			print $ADDRFILE "\n";

		}

		print $ADDRFILE "$sets_info->{tags}[$tag_num]{addresslabel}\n";

	}
	close $ADDRFILE;

	# copy the UPS address file to the fulfillment folder

	my $target_dir = $jobbag->{extra_options}{fulfillment_dir} . '/UPS';
	if ( $jobbag->{environment} !~ /Production/i ) {
		$target_dir .= '/UAT';
	}

	print "\nCopying $address_label_fname to $target_dir\n";

	Utilities::motus(
		action      => 'copy',
		source      => $address_label_fname,
		target      => $target_dir,
		threshhold  => $jobbag->{extra_options}{threshhold} || 15,
		sleep       => $jobbag->{extra_options}{sleep} || 10,
		alert_every => $jobbag->{extra_options}{alert_every} || 10,
	);

	return;
}

sub _create_UPSBulk_addressfile {
	my ( $this, $gpd_name, $jobbag ) = @_;

	my $batch_sort_tag_key;

	my $sets_info = UtilsGpdReaders::get_sets_info(
		filename      => $gpd_name,
		incl_tags     => 1,
		set_tags_spec => [ '^addresslabel', '^dispatch:product' ],
	) or Utils::JEF_Exception::terminate("\nNo address label/dispatch product set tags found in $gpd_name.");

	my $batch_tracker = 1;
	foreach my $tag_num ( 1 .. @{ $sets_info->{tags} } - 1 ) {
		# first set of every batch
		if ( ( $tag_num == 1 ) or ( $batch_sort_tag_key ne $sets_info->{tags}[$tag_num]{'dispatch:product'} ) ) {
			$batch_sort_tag_key = $sets_info->{tags}[$tag_num]{'dispatch:product'};

			$gpd_name =~ s/_|\.gpd//gi;
			my $address_label_fname = $gpd_name . '_' . '0' . $batch_tracker++ . '.csv';

			open my $ADDRFILE, '>>', $address_label_fname
				or Utils::JEF_Exception::terminate("\nFailed to open $address_label_fname : $!");
			print $ADDRFILE 'CustomerID,'
				. 'CompanyName,'
				. 'Attention,'
				. 'Address1,'
				. 'Address2,'
				. 'Address3,' . 'City,'
				. 'State,'
				. 'Zipcode,'
				. 'Email,'
				. 'Phone,'
				. 'Reference1,'
				. 'Reference2,'
				. 'Weight,'
				. 'Service,'
				. 'PackageType,'
				. 'BillTransportationTo,'
				. 'bill_to_name,'
				. 'bill_to_address,'
				. 'bill_to_country,'
				. 'bill_to_zip,'
				. 'bill_to_city,'
				. 'bill_to_state,'
				. 'bill_to_account' . "\n";

			# add the address label row
			print $ADDRFILE "$sets_info->{tags}[$tag_num]{addresslabel}\n";
			close $ADDRFILE;

			# copy the UPSBulk address file to the fulfillment folder
			my $target_dir = $jobbag->{extra_options}{fulfillment_dir} . '/UPS';
			if ( $jobbag->{environment} !~ /Production/i ) {
				$target_dir .= '/UAT';
			}

			print "\nCopying $address_label_fname to $target_dir\n";

			Utilities::motus(
				action      => 'copy',
				source      => $address_label_fname,
				target      => $target_dir,
				threshhold  => $jobbag->{extra_options}{threshhold} || 15,
				sleep       => $jobbag->{extra_options}{sleep} || 10,
				alert_every => $jobbag->{extra_options}{alert_every} || 10,
			);
		}
	}

	return;
}

sub _create_FedExBulk_addressfile {
	my ( $this, $gpd_name, $jobbag ) = @_;

	my $batch_sort_tag_key;

	my $sets_info = UtilsGpdReaders::get_sets_info(
		filename      => $gpd_name,
		incl_tags     => 1,
		set_tags_spec => [ '^addresslabel', '^dispatch:product' ],
	) or Utils::JEF_Exception::terminate("\nNo address label/dispatch product set tags found in $gpd_name.");

	my $batch_tracker = 1;
	foreach my $tag_num ( 1 .. @{ $sets_info->{tags} } - 1 ) {
		# first set of every batch
		if ( ( $tag_num == 1 ) or ( $batch_sort_tag_key ne $sets_info->{tags}[$tag_num]{'dispatch:product'} ) ) {
			$batch_sort_tag_key = $sets_info->{tags}[$tag_num]{'dispatch:product'};

			$gpd_name =~ s/_|\.gpd//gi;
			my $address_label_fname = $gpd_name . '_' . '0' . $batch_tracker++ . '.xls';

			open my $ADDRFILE, '>>', $address_label_fname
				or Utils::JEF_Exception::terminate("\nFailed to open $address_label_fname : $!");

			# add the address label row
			print $ADDRFILE "$sets_info->{tags}[$tag_num]{addresslabel}\n";

			close $ADDRFILE;

			# copy the FedExBulk address file to the fulfillment folder
			my $target_dir = $jobbag->{extra_options}{fulfillment_dir} . '/FedEx';
			if ( $jobbag->{environment} !~ /Production/i ) {
				$target_dir .= '/UAT';
			}

			print "\nCopying $address_label_fname to $target_dir\n";

			Utilities::motus(
				action      => 'copy',
				source      => $address_label_fname,
				target      => $target_dir,
				threshhold  => $jobbag->{extra_options}{threshhold} || 15,
				sleep       => $jobbag->{extra_options}{sleep} || 10,
				alert_every => $jobbag->{extra_options}{alert_every} || 10,
			);
		}
	}

	return;
}

sub _create_FedEx_addressfile {
	my ( $this, $gpd_name, $jobbag ) = @_;

	my $sets_info = UtilsGpdReaders::get_sets_info(
		filename      => $gpd_name,
		incl_tags     => 1,
		set_tags_spec => ['^addresslabel'],
	);

	my $address_label_fname = $gpd_name . '.xls';
	$address_label_fname =~ s/_|\.gpd//gi;

	open my $ADDRFILE, '>>', $address_label_fname
		or Utils::JEF_Exception::terminate("\nFailed to open $address_label_fname : $!");

	foreach my $tag_num ( 1 .. @{ $sets_info->{tags} } - 1 ) {
		print $ADDRFILE "$sets_info->{tags}[$tag_num]{addresslabel}\n";
	}

	close $ADDRFILE;
	# copy the UPS address file to the fulfillment folder

	my $target_dir = $jobbag->{extra_options}{fulfillment_dir} . '/FedEx';
	if ( $jobbag->{environment} !~ /Production/i ) {
		$target_dir .= '/UAT';
	}

	print "\nCopying $address_label_fname to $target_dir\n";
	Utilities::motus(
		action      => 'copy',
		source      => $address_label_fname,
		target      => $target_dir,
		threshhold  => $jobbag->{extra_options}{threshhold} || 15,
		sleep       => $jobbag->{extra_options}{sleep} || 10,
		alert_every => $jobbag->{extra_options}{alert_every} || 10,
	);

	return;
}

sub _create_reports {
	my ( $this, $jobbag ) = @_;

	my $report_out_dir =
		  CcsCommon::get_setting( 'GENERAL', 'datain_folder' ) . '\\'
		. $jobbag->{__config}{job}{client_name} . '_'
		. $jobbag->{__config}{job}{client_code} . '\\'
		. $jobbag->{__config}{job}{job_code} . '\\Out';

	# Positive Pay Report
	print "\nGenerating positive pay report...";
	foreach my $pospay_file ( keys %{ $jobbag->{positive_report_details} } ) {
		##
		# Positive Pay Report
		##

		open my $REPORT, '>>', $pospay_file or Utils::JEF_Exception::terminate("Failed to open $pospay_file: $!");

		foreach my $row ( @{ $jobbag->{positive_report_details}{$pospay_file} } ) {
			print $REPORT $row->{record} . "\n";
		}

		close $REPORT;

		# copy the Positive Pay report(s) to the ftp out folder
		Utilities::motus(
			action      => 'copy',
			source      => $pospay_file,
			target      => $report_out_dir,
			threshhold  => $jobbag->{extra_options}{threshhold} || 15,
			sleep       => $jobbag->{extra_options}{sleep} || 10,
			alert_every => $jobbag->{extra_options}{alert_every} || 10,
		);
	}

	return 1;
}

sub _include_origxmlfile {
	my ( $this, $datain_path, $jobbag ) = @_;

	my $data_file_path = JEF::get_params( $jobbag, 'data_dir' );    #data directory from the processing machine

	my @poxml_files = grep { /\.po\.xml$/i } @{ JEF::get_params( $jobbag, 'data_files' ) };

	foreach my $poxml (@poxml_files) {
		my $origxml_file = $poxml;
		$origxml_file =~ s/\.po\.xml$//i;
		( my $orig_pain001 = $origxml_file ) =~ s/id\.xml/xml/i;

		if ( -e "$datain_path\\$origxml_file" ) {
			print "\n moving the corresponding original file: $datain_path\\$origxml_file to $data_file_path...";

			Utilities::motus(
				action      => 'move',                                  # change to move
				source      => "$datain_path\\$origxml_file",
				target      => $data_file_path,
				threshhold  => $jobbag->{cl_opts}{threshhold} || 15,
				sleep       => $jobbag->{cl_opts}{sleep} || 15,
				alert_every => $jobbag->{cl_opts}{alert_every} || 10,
			);
		}

		if ( -e "$datain_path\\$orig_pain001" ) {
			print "\n moving the original pain.001 file: $datain_path\\$orig_pain001 to $data_file_path...";

			Utilities::motus(
				action      => 'move',                                  # change to move
				source      => "$datain_path\\$orig_pain001",
				target      => $data_file_path,
				threshhold  => $jobbag->{cl_opts}{threshhold} || 15,
				sleep       => $jobbag->{cl_opts}{sleep} || 15,
				alert_every => $jobbag->{cl_opts}{alert_every} || 10,
			);
		}
	}

	return 1;

}

sub _create_final_ACK_report {
	my ( $this, $jobbag ) = @_;

	if ( !defined $jobbag->{file_issues}{group}{status} ) {    # if undef it's not set to either RJCT or PART
		$jobbag->{file_issues}{group}{status} = 'ACCP';
	}

	# get the original xml file name and put it into jobbag
	my $data_file_path = $jobbag->{extra_options}{input_folder};
	my @poxml_files = grep { /\.po\.xml$/i } @{ JEF::get_params( $jobbag, 'data_files' ) };

	foreach my $poxml (@poxml_files) {
		my $origxml_file = $poxml;
		$origxml_file =~ s/\.po\.xml$//i;
		$jobbag->{'iso_xml_file'} = $origxml_file;
	}

	# get the group header and information and put it into the jobbag
	my $file = DataFile::XML2->open( "$data_file_path/$jobbag->{'iso_xml_file'}", 1 );    # pull in the entire record

	while ( my $rec = $file->next() ) {
		# get information needed for GrpHdr for ACK File
		$jobbag->{ack_info}{GrpHdr} = {
			message_id       => $rec->{CstmrCdtTrfInitn}{GrpHdr}{MsgId},
			control_sum      => $rec->{CstmrCdtTrfInitn}{GrpHdr}{CtrlSum},
			num_transactions => $rec->{CstmrCdtTrfInitn}{GrpHdr}{NbOfTxs},
			cre_dt_time      => $rec->{CstmrCdtTrfInitn}{GrpHdr}{CreDtTm},
		};
	}
	$file->close;

	ISO_Utils::write_Ack($jobbag);

	# get ftp out path
	my $bmo_ftp_path = CcsCommon::get_setting( 'reports', 'bmo_outbound_ftp' );    # UAT/PROD

	my $data_file_dir = JEF::get_params( $jobbag, 'data_dir' );
	my $ack_file = $jobbag->{'ack_file'};

	my $attachment = "$data_file_dir/$ack_file";

	#put reports on ftp path
	if ( "$data_file_dir/$ack_file" && $bmo_ftp_path ) {
		Utilities::motus(
			action => 'move',
			source => "$data_file_dir/$ack_file",
			target => $bmo_ftp_path,
		);
	}

	return;
}

sub _create_pdf_and_zip {
	my ( $this, $gpd_name, $jobbag ) = @_;

	my $sets_info = UtilsGpdReaders::get_sets_info(
		filename      => $gpd_name,
		incl_tags     => 1,
		set_tags_spec => [ 'account_number', 'check_number', 'party_id', 'tran_id', 'pdf_image_flag', 'serial_number' ],
	) or Utils::JEF_Exception::terminate("\nNo party_id, tran_id and pdf_image_flag set tag founds at $gpd_name.");

	my $cmd;
	my $pdf_fname;
	my $zip_fname;

	my $exe = NA::Std::Utils::get7zipExecutablePath();

	# zip filenaming Convention
	#  UAT: COMPAYUS.[Customer ID].CHKIMGUST.YYYYMMDD.HHMMSS.PDF.NXXXXXX.zip
	#  Prod: COMPAYUS.[Customer ID].CHKIMGUSP.YYYYMMDD.HHMMSS.PDF.NXXXXXX.zip

	my $zip_envt_id = ( $jobbag->{environment} !~ /Production/i ) ? 'CHKIMGUST' : 'CHKIMGUSP';
	my $proc_date_time = _process_date_time();

	foreach my $tag_num ( 1 .. @{ $sets_info->{tags} } - 1 ) {

		if ( $sets_info->{tags}[$tag_num]{pdf_image_flag} ) {
			$pdf_fname =
"$sets_info->{tags}[$tag_num]{party_id}.$sets_info->{tags}[$tag_num]{account_number}.$sets_info->{tags}[$tag_num]{check_number}.$sets_info->{tags}[$tag_num]{tran_id}.pdf";
			$cmd = "$ENV{CCS_RESOURCE}\\Global\\Scripts\\g2p.cmd --sets $tag_num --pdf_file $pdf_fname $gpd_name";
			system($cmd);
			if ($?) {
				Utils::JEF_Exception::terminate("Something unexpected happened with $cmd\n$?");
			}

			$zip_fname =
"COMPAYUS.$sets_info->{tags}[$tag_num]{party_id}.$zip_envt_id.$proc_date_time.PDF.$sets_info->{tags}[$tag_num]{serial_number}.zip";

			$cmd = "$exe a $zip_fname $pdf_fname";
			#}
			print "EXECUTING: $exe to add $pdf_fname into $zip_fname\n";
			`$cmd`;
			if ($?) {
				Utils::JEF_Exception::terminate("Failed to add $pdf_fname to the zip file, $zip_fname. Error: $?");
			}
			else {
				unlink($pdf_fname);
			}
		}
	}

	# copy the zip file(s) to the FTP out folder

	my $ftp_out_dir =
		  CcsCommon::get_setting( 'GENERAL', 'datain_folder' ) . '\\'
		. $jobbag->{__config}{job}{client_name} . '_'
		. $jobbag->{__config}{job}{client_code} . '\\'
		. $jobbag->{__config}{job}{job_code} . '\\Out';

	foreach my $pdf_zipfile ( glob('COMPAYUS.*.PDF.N*.zip') ) {
		print "\nCopying $pdf_zipfile to $ftp_out_dir\n";

		Utilities::motus(
			action      => 'copy',
			source      => $pdf_zipfile,
			target      => $ftp_out_dir,
			threshhold  => $jobbag->{extra_options}{threshhold} || 15,
			sleep       => $jobbag->{extra_options}{sleep} || 10,
			alert_every => $jobbag->{extra_options}{alert_every} || 10,
		);
	}

	return;
}

sub _process_date_time {

	my ( $second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings ) =
		localtime();

	$month++;
	$minute += 10;
	my $year = $yearOffset + 1900;
	my $proc_date = sprintf( "%04d%02d%02d.%02d%02d%02d", $year, $month, $dayOfMonth, $hour, $minute, $second );

	return $proc_date;
}

sub _include_client_reports {
	my ( $this, $datain_path, $jobbag ) = @_;

	my $data_file_path = JEF::get_params( $jobbag, 'data_dir' );    #data directory from the processing machine

	print "\n\nChecking $datain_path...";

	opendir my ($dh), $datain_path or die $!;
	my @zip_files = grep { /Reports.*\.zip$/i } readdir $dh;
	close $dh;

	if (@zip_files) {
		print "found  @zip_files\n";
	}

	foreach my $zip (@zip_files) {

		if ( -e "$datain_path\\$zip" ) {
			print "\n moving client zip file: $datain_path\\$zip to $data_file_path...";

			Utilities::motus(
				action      => 'move',                                  # change to move
				source      => "$datain_path\\$zip",
				target      => $data_file_path,
				threshhold  => $jobbag->{cl_opts}{threshhold} || 15,
				sleep       => $jobbag->{cl_opts}{sleep} || 15,
				alert_every => $jobbag->{cl_opts}{alert_every} || 10,
			);
		}
	}

	return 1;

}

1;
