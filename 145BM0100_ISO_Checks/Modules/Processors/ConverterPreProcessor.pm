package ConverterPreProcessor;
################################################################################
# Reuse code from EWB and %CCS_RESOURCE%\Regional\US\Scripts\BMO\Read_XML.pl:
#   script reading XML data file to HASH
#   and create acknowledgement report XML file
################################################################################

use 5.010;

use strict;
use warnings;

use base qw(GenericProcessor);
use Data::Dumper;
use Logger::Log;
use Getopt::Long qw(GetOptionsFromArray :config pass_through);

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

# Global/Std
use CcsSmtp;
# Regional
use NA::Std::Paths;
use CcsCommon;
use SOAP::Lite;
use CcsDb;
use DataFile::XML2;
use File::Copy;
use DateTime;
use Time::HiRes qw/gettimeofday/;
use Time::localtime;
use DataFile::XMLCheck;
use XML::Writer;
use IO::File;
use ISO_Utils;

################################################################################

# JEF-----------------------------------------------------------------

sub run {
	my ( $this, $jobbag ) = @_;

	$this->SUPER::run($jobbag);

	$jobbag->{extra_options} = {
		ignore_file       => undef,
		threshhold        => undef,
		sleep             => undef,
		alert_every       => undef,
		corropack_group   => undef,
		corropack_product => undef,
		corropack_id      => undef,
		doc_comp          => undef,
		convert           => undef,
		acknowledged      => undef,
		ftp_out_folder    => undef,
		archive           => undef,
		email1            => undef,
		email2            => undef,
		bank_address1     => undef,
		db_retries        => undef,
		db_retry_time     => undef,
	};

	if ( defined $jobbag->{__run_params}{extra} ) {
		GetOptionsFromArray(
			$jobbag->{__run_params}{extra}, $jobbag->{extra_options},
			'threshhold=i',                 'sleep=i',
			'alert_every=i',                'corropack_group=s',
			'corropack_product=s',          'corropack_id=s',
			'doc_comp',                     'convert',
		);
	}

	GetOptions(
		'acknowledged=s'   => \$jobbag->{extra_options}{acknowledged},
		'ftp_out_folder=s' => \$jobbag->{extra_options}{ftp_out_folder},
		'archive=s'        => \$jobbag->{extra_options}{archive},
		'email1=s'         => \$jobbag->{extra_options}{email1},
		'email2=s'         => \$jobbag->{extra_options}{email2},
		'bank_address1=s'  => \$jobbag->{extra_options}{bank_address1},
		'db_retries=s'     => \$jobbag->{extra_options}{db_retries},
		'db_retry_time=s'  => \$jobbag->{extra_options}{db_retry_time},
	);

	my $data_dir = JEF::get_params( $jobbag, 'data_dir' );

# first check - make sure we have two files that look like the ones we need and stash them in a variable in case we need them later
	foreach my $input_file ( @{ JEF::get_params( $jobbag, 'data_files' ) } ) {

		if ( $input_file =~ /id\.xml$/i ) {
			$jobbag->{'iso_xml_file'} = $input_file;
			( $jobbag->{'orig_xml_file'} = $jobbag->{'iso_xml_file'} ) =~ s/id\.xml/xml/i;
		}
		else {
			Utils::JEF_Exception::terminate("Unknown file: '$input_file'");
		}
	}
	my $file_name = $jobbag->{'iso_xml_file'};

	# subsequent processing taken from %CCS_RESOURCE%\Regional\US\Scripts\BMO\Read_XML.pl
	# with new code added for file and transaction level checks for WR-483

	# work around to test if the file can be opened and read before sending to XMLCheck for validation
	open( my $TEST_FH, '<', "$data_dir/$file_name" )
		or Utils::JEF_Exception::terminate(
		"Unable to open file $data_dir/$file_name or other network issue: $!\nPlease requeue.");

	close $TEST_FH;

	# check input XML file if it is good or bad
	my $rc = DataFile::XMLCheck::validate( xml_file => "$data_dir/$jobbag->{'iso_xml_file'}" );

	my $msg;

	# get Ack file name
	my $date_time = _timestamp();
	$jobbag->{convert_timestamp} = $date_time;

	# current production naming convention P.COMSHARUS.21009536.PAIN001.20230705144549.N030534.XML
	#my ( $t, $comsharus, $customer_id, $pain001, $filedatetime, $serialnumber, $xml );
	#	split( /\./, $jobbag->{'orig_xml_file'} );

	# we do *not* use $comsharus, $pain001 and $xml
	# $t, $comsharus, $customer_id, $pain001, $type, $filedatetime, $serialnumber, $xml
	my ( $t, $customer_id, $type, $filedatetime, $serialnumber );
	my $ack_file = '';
	if ( $file_name =~ /\.(VEND|NONVEND)\./ ) {
		( $t, undef, $customer_id, undef, $type, $filedatetime, $serialnumber, undef ) =
			split( /\./, $file_name );
		# COMPAYUS.[Customer ID].IPAIN002UST.VEND.YYYYMMDD.HHMMSS.PAIN002.NXXXXXX.xml
		$ack_file = "COMPAYUS.$customer_id.IPAIN002US$t.$type.$filedatetime.PAIN002.$serialnumber.xml";
	}
	else {
		( $t, undef, $customer_id, undef, $filedatetime, $serialnumber, undef ) =
			split( /\./, $file_name );
		$ack_file = "COMPAYUS.$customer_id.IPAIN002US$t.$filedatetime.PAIN002.$serialnumber.xml";
	}

	$jobbag->{'ack_file'} = $ack_file;

	if ( !$rc ) {    # bad XML input file
		print "\nBad XML\n";
		# send email notification to BMO, not sending ack attachment
		$msg =
"$file_name\n\nThe file received by Computershare is not a well-formed XML extension file.\n\nThis is an automated email. If you are experiencing problems, or you are receiving this in error, please contact Computershare Communication Services and ask for the Client Account Manager.\n\nThank you\n";
		email( "Check Printing Mail File Error", $msg, $jobbag->{extra_options}{email2}, undef );

		move( "$data_dir/$file_name", "$jobbag->{extra_options}{archive}/$file_name" )
			or die "Move file to Archive dir failed: $!";

		Utils::JEF_Exception::terminate('Client sent bad input XML file');
	}
	elsif ($rc) {
		# initial check for good XML passed, now begin series of file level checks
		print "\nGood XML\n";
		my $status           = 'ACCP';
		my $reason_code      = '';
		my $cum_cheque_total = '';
		my $business_reason  = '';

		# open data file and read into hash
		my $file = DataFile::XML2->open( "$data_dir/$jobbag->{'iso_xml_file'}", 1 );    # pull in the entire record

		$jobbag->{'file_issues'}{group} = {
			status          => undef,
			reason_code     => undef,
			business_reason => undef,
			date_time       => undef,
		};

		$jobbag->{reject_type}{file}        = 0;
		$jobbag->{reject_type}{transaction} = 0;

		## file-level validation checks

		while ( my $rec = $file->next() ) {

			my $rec = ISO_Utils::fake_force_array($rec);

			# get information needed for GrpHdr for ACK File
			$jobbag->{ack_info}{GrpHdr} = {
				message_id       => $rec->{CstmrCdtTrfInitn}[0]{GrpHdr}[0]{MsgId}[0],
				control_sum      => $rec->{CstmrCdtTrfInitn}[0]{GrpHdr}[0]{CtrlSum}[0],
				num_transactions => $rec->{CstmrCdtTrfInitn}[0]{GrpHdr}[0]{NbOfTxs}[0],
			};

			if ( !defined $rec->{CstmrCdtTrfInitn}[0]{GrpHdr}[0]{NbOfTxs}[0]
				|| $rec->{CstmrCdtTrfInitn}[0]{GrpHdr}[0]{NbOfTxs}[0] < 1 )
			{
				$status          = 'RJCT';
				$reason_code     = 'TD03';
				$business_reason = 'File contains zero transactions';

				$jobbag->{'file_issues'}{group}{status}          = $status;
				$jobbag->{'file_issues'}{group}{reason_code}     = $reason_code;
				$jobbag->{'file_issues'}{group}{business_reason} = $business_reason;
				$jobbag->{'file_issues'}{group}{date_time}       = $date_time;
				$jobbag->{'file_issues'}{group}{transaction_id}  = $rec->{CstmrCdtTrfInitn}[0]{PmtInf}[0]{PmtInfId}[0];

				$jobbag->{reject_type}{file} = 1;
			}

			# accummulate a running total of all check amounts
			foreach my $pmt_inf ( @{ $rec->{CstmrCdtTrfInitn}[0]{PmtInf} } ) {
				foreach my $tx_inf ( @{ $pmt_inf->{CdtTrfTxInf} } ) {
					$jobbag->{cum_cheque_total} = sprintf( "%.2f",
						( $jobbag->{cum_cheque_total} || 0 ) + ( $tx_inf->{Amt}[0]{InstdAmt}[0]{content}[0] || 0 ) );
				}
			}

		}    # end while
		     # final file level check to ensure that the CtrlSum and Accumulated check sum match
		$jobbag->{ack_info}{GrpHdr}{control_sum} = sprintf( "%.2f", $jobbag->{ack_info}{GrpHdr}{control_sum} );
		$jobbag->{cum_cheque_total} = sprintf( "%.2f", $jobbag->{cum_cheque_total} );

		if ( $jobbag->{ack_info}{GrpHdr}{control_sum} ne $jobbag->{cum_cheque_total} ) {
			$status          = 'RJCT';
			$reason_code     = 'AM10';
			$business_reason = 'Control Sum does not equal the total sum of all check in the file';

			$jobbag->{'file_issues'}{group}{status}          = $status;
			$jobbag->{'file_issues'}{group}{reason_code}     = $reason_code;
			$jobbag->{'file_issues'}{group}{business_reason} = $business_reason;
			$jobbag->{'file_issues'}{group}{date_time}       = $date_time;
			$jobbag->{'file_issues'}{group}{transaction_id}  = $jobbag->{'file_issues'}{group}{transaction_id};

			$jobbag->{reject_type}{file} = 1;
		}

	}    # end good xml
	print "End of ConverterPreProcessor\n";
	# if we get to this point, there are no file-level issues
	# transaction-level processing happens in the converter

	return;
}

sub email {
	my ( $subject, $body, $addresses, $attachment ) = @_;

	my %mail = (
		to           => [ split( ',', $addresses ) ],
		from         => '!USCSBURProgramming@computershare.com',
		fromdispname => '!USCSBURProgramming@computershare.com',
		recipients   => [$addresses],
		subject      => $subject,
		body         => [$body],
		attachments => defined $attachment ? [ split( ',', $attachment ) ] : []
	);

	CcsSmtp::SendMail( \%mail );

	return 1;
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

1;

