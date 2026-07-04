package ISO_Utils;
################################################################################
# Utility subs here are used by two or more modules during BMO ISO processing
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
use NA::Std::Paths;
use XML::Writer;
use Time::localtime;

# this sub accepts parameters for writing to the Acknowledgement file that is
# created during converter preprocessing, updated during Doc Comp and then
# sent to BMO at the end of Doc Comp.
# WR-483
sub write_Ack {
	my ($jobbag) = @_;
	my ( $writer, $output );

	if ( defined $jobbag->{'file_issues'}{group}{status}
		&& $jobbag->{'file_issues'}{group}{status} =~ /ACCP|PART|RJCT/ )
	{
		( $writer, $output ) = _init_write_Ack($jobbag);
		_write_Ack_GrpHdr( $writer, $jobbag );
		_write_Ack_GrpInf( $writer, $jobbag );
		_write_Ack_PmtInf( $writer, $jobbag );
		_close_write_Ack( $writer, $output );
	}
	elsif ( defined $jobbag->{pmt_inf}{group}{status} =~ /ACCP|PART|RJCT/ ) {
		( $writer, $output ) = _init_write_Ack($jobbag);
		_write_Ack_GrpHdr( $writer, $jobbag );
		_write_Ack_GrpInf( $writer, $jobbag );
		_write_Ack_PmtInf( $writer, $jobbag );
		_close_write_Ack( $writer, $output );
	}
	else {
		Utils::JEF_Exception::terminate("Unknown file or PmtInf status");
	}

	return;
}

sub _init_write_Ack {

	my ($jobbag) = @_;

	Logger::Log->new();

	my $ack_file;

	my $doc_comp_trigger_dir = JEF::get_params( $jobbag, 'data_dir' );    #data directory from the processing machine

	if ( defined $jobbag->{'ack_file'} && $jobbag->{'ack_file'} ne '' ) {
		$ack_file = $jobbag->{'ack_file'};
	}
	else {
		if ( !$jobbag->{'orig_xml_file'} ) {
			Utils::JEF_Exception::terminate("\$jobbag->{'orig_xml_file'} is not set\n$!");
		}
		else {
			# inputfile naming convention: T.COMSHARUS.[Customer ID].PAIN001.YYYYMMDDHHMMSS.NXXXXXX.xml
			my ( $t, $comsharus, $customer_id, $pain001, $filedatetime, $serialnumber, $xml ) =
				split( /\./, $jobbag->{'orig_xml_file'} );

			$ack_file =
				  'COMPAYUS.'
				. $customer_id
				. '.IPAIN002US'
				. $t . '.'
				. $filedatetime
				. '.PAIN002.'
				. $serialnumber . '.xml';

			$jobbag->{'ack_file'} = "$ack_file";
		}
	}

	# open output file
	my $output = IO::File->new(">$doc_comp_trigger_dir/$ack_file")
		|| Utils::JEF_Exception::terminate("Not able to open XML file $doc_comp_trigger_dir/$ack_file for writing\n$!");

	my $xsi_uri = "http://www.w3.org/2001/XMLSchema-instance";
	my $xmlns   = "urn:iso:std:iso:20022:tech:xsd:pain.002.001.03";
	my $writer  = XML::Writer->new(
		OUTPUT      => $output,
		DATA_MODE   => 1,
		DATA_INDENT => 2,
		NAMESPACES  => 1,
		PREFIX_MAP  => { $xsi_uri => 'xsi', $xmlns => '' },
		FORCED_NS_DECLS => [ $xsi_uri, $xmlns ],
		UNSAFE          => 1,
	);

	$writer->xmlDecl("UTF-8");

	# initialize ACK file
	$writer->startTag('Document');
	$writer->startTag('CstmrPmtStsRpt');

	return ( $writer, $output );

}

sub _close_write_Ack {
	my ( $writer, $output ) = @_;

	$writer->endTag('CstmrPmtStsRpt');
	$writer->endTag('Document');
	$writer->end();
	$output->close();

	return;
}

sub _write_Ack_GrpHdr {
	my ( $writer, $jobbag ) = @_;

	$writer->startTag('GrpHdr');
	$writer->dataElement( 'MsgId',   $jobbag->{ack_info}{GrpHdr}{message_id} );
	$writer->dataElement( 'CreDtTm', _timestamp() );
	$writer->startTag('InitgPty');
	$writer->dataElement( 'Nm', 'BMO' );
	$writer->startTag('Id');
	$writer->startTag('OrgId');
	$writer->startTag('Othr');
	$writer->dataElement( 'Id', 'BOFMCAM2' );
	$writer->startTag('SchmeNm');
	$writer->dataElement( 'Cd', 'BANK' );
	$writer->endTag('SchmeNm');
	$writer->endTag('Othr');
	$writer->endTag('OrgId');
	$writer->endTag('Id');
	$writer->startTag('CtctDtls');
	$writer->dataElement( 'Nm',       'BMO TPS Helpdesk' );
	$writer->dataElement( 'PhneNb',   '+1-800-565-6444' );
	$writer->dataElement( 'EmailAdr', 'TPSCAD.HelpDesk@bmo.com' );
	$writer->dataElement( 'Othr',     'CA:416-867-4818 / US:1-866-867-2173' );
	$writer->endTag('CtctDtls');
	$writer->endTag('InitgPty');
	$writer->endTag('GrpHdr');

	return;
}

sub _write_Ack_GrpInf {
	my ( $writer, $jobbag ) = @_;

	my $status;

	# non repeatable block now, may be repeatable in future
	# OrgnlGrpInfAndSts
	$writer->startTag('OrgnlGrpInfAndSts');

	$writer->dataElement( 'OrgnlMsgId',   $jobbag->{ack_info}{GrpHdr}{message_id} );
	$writer->dataElement( 'OrgnlMsgNmId', 'pain.001' );
	$writer->dataElement( 'OrgnlNbOfTxs', $jobbag->{ack_info}{GrpHdr}{num_transactions} );
	$writer->dataElement( 'OrgnlCtrlSum', $jobbag->{ack_info}{GrpHdr}{control_sum} );

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

	$writer->dataElement( 'GrpSts', $status );

	if ( defined $jobbag->{accept} && $jobbag->{accept} >= 1 ) {
		$writer->startTag('NbOfTxsPerSts');
		$writer->dataElement( 'DtldNbOfTxs', $jobbag->{accept} );
		$writer->dataElement( 'DtldSts',     'ACCP' );
		$writer->dataElement( 'DtldCtrlSum', $jobbag->{accept_chk_amount} || '' );
		$writer->endTag('NbOfTxsPerSts');
	}
	if ( defined $jobbag->{reject} && $jobbag->{reject} >= 1 ) {
		$writer->startTag('NbOfTxsPerSts');
		$writer->dataElement( 'DtldNbOfTxs', $jobbag->{reject} );
		$writer->dataElement( 'DtldSts',     'RJCT' );
		$writer->dataElement( 'DtldCtrlSum', $jobbag->{reject_chk_amount} || '' );
		$writer->endTag('NbOfTxsPerSts');
	}

	$writer->endTag('OrgnlGrpInfAndSts');

	return;
}

sub _write_Ack_PmtInf {
	my ( $writer, $jobbag ) = @_;

	if ( defined $jobbag->{proc_transactions} ) {

		# get total count of transaction ids from $jobbag->{proc_transactions}
		# this drives the number of OrgnlPmtInfAndSts tags to be written out
		my $overall_total = ( $jobbag->{accept} || 0 ) + ( $jobbag->{reject} || 0 );

		return if ( 0 == $overall_total );

		my @ACCP_PmtInfID;
		# get list of ACCP PmtInfID to use for a loop

		my %check_trans_id;
		foreach my $tr_accp ( @{ $jobbag->{proc_transactions}{transaction}{accept} } ) {
			if ( exists $check_trans_id{ $tr_accp->{transaction_id} } ) {
				next;
			}
			else {
				push @ACCP_PmtInfID, $tr_accp->{transaction_id};
				$check_trans_id{ $tr_accp->{transaction_id} } = 1;
			}

		}
		foreach my $tr_rjct ( @{ $jobbag->{proc_transactions}{transaction}{reject} } ) {
			if ( exists $check_trans_id{ $tr_rjct->{transaction_id} } ) {
				next;
			}
			else {
				push @ACCP_PmtInfID, $tr_rjct->{transaction_id};
				$check_trans_id{ $tr_rjct->{transaction_id} } = 1;
			}

		}

		foreach my $pmt_inf_id (@ACCP_PmtInfID) {
			$writer->startTag('OrgnlPmtInfAndSts');
			$writer->dataElement( 'OrgnlPmtInfId', $pmt_inf_id );

			my ( $accp_status, $accp_currency, $accp_check_amount, $accp_payment_id );
			my $trans_id_accp_cum_amt;
			my $trans_id_accpt_cnt;

			my (
				$rjct_status,     $rjct_currency,    $rjct_check_amount,
				$rjct_payment_id, $rjct_reason_code, $rjct_business_reason
			);
			my $trans_id_rjct_cum_amt;
			my $trans_id_rjct_cnt;

			#need to accumulate transaction count and check totals for each $pmt_inf_id
			foreach my $tr_accp ( @{ $jobbag->{proc_transactions}{transaction}{accept} } ) {

				if ( $pmt_inf_id eq $tr_accp->{transaction_id} ) {
					$accp_check_amount = $tr_accp->{check_amount};

					$trans_id_accpt_cnt++;
					$trans_id_accp_cum_amt = sprintf( "%.2f", ( $trans_id_accp_cum_amt || 0 ) + $accp_check_amount );
				}
				else {
					next;
				}
			}

			foreach my $tr_rjct ( @{ $jobbag->{proc_transactions}{transaction}{reject} } ) {

				if ( $pmt_inf_id eq $tr_rjct->{transaction_id} ) {
					$rjct_check_amount = $tr_rjct->{check_amount};

					$trans_id_rjct_cnt++;
					$trans_id_rjct_cum_amt =
						sprintf( "%.2f", ( $trans_id_rjct_cum_amt || 0 ) + $tr_rjct->{check_amount} );
				}
			}

			if ( defined $trans_id_accpt_cnt && defined $trans_id_accp_cum_amt ) {
				$writer->startTag('NbOfTxsPerSts');
				$writer->dataElement( 'DtldNbOfTxs', $trans_id_accpt_cnt );
				$writer->dataElement( 'DtldSts',     'ACCP' );
				$writer->dataElement( 'DtldCtrlSum', $trans_id_accp_cum_amt );
				$writer->endTag('NbOfTxsPerSts');
			}
			if ( defined $trans_id_rjct_cnt && defined $trans_id_rjct_cum_amt ) {
				$writer->startTag('NbOfTxsPerSts');
				$writer->dataElement( 'DtldNbOfTxs', $trans_id_rjct_cnt );
				$writer->dataElement( 'DtldSts',     'RJCT' );
				$writer->dataElement( 'DtldCtrlSum', $trans_id_rjct_cum_amt );
				$writer->endTag('NbOfTxsPerSts');
			}
			foreach my $tr_accp ( @{ $jobbag->{proc_transactions}{transaction}{accept} } ) {
				if ( defined $trans_id_accpt_cnt && defined $trans_id_accp_cum_amt ) {
					my $trans_id_cum_amt = 0;

					if ( $pmt_inf_id eq $tr_accp->{transaction_id} ) {
						$accp_status       = $tr_accp->{status};
						$accp_payment_id   = $tr_accp->{payment_id};
						$accp_currency     = $tr_accp->{currency};
						$accp_check_amount = $tr_accp->{check_amount};
					}
					else {
						next;
					}

					$writer->startTag('TxInfAndSts');
					$writer->dataElement( 'OrgnlEndToEndId', $accp_payment_id );
					$writer->dataElement( 'TxSts',           $accp_status );
					$writer->startTag('OrgnlTxRef');
					$writer->startTag('Amt');
					my $attr_info =
						"\n            <InstdAmt Ccy=\"$accp_currency\">$accp_check_amount</InstdAmt>\n          ";
					$writer->raw($attr_info);
					$writer->endTag('Amt');
					$writer->dataElement( 'ReqdExctnDt', $tr_accp->{check_date} );
					$writer->endTag('OrgnlTxRef');

					$writer->endTag('TxInfAndSts');
				}
			}

			foreach my $tr_rjct ( @{ $jobbag->{proc_transactions}{transaction}{reject} } ) {

				if ( defined $trans_id_rjct_cnt && defined $trans_id_rjct_cum_amt ) {
					if ( $pmt_inf_id eq $tr_rjct->{transaction_id} ) {
						$rjct_status          = $tr_rjct->{status};
						$rjct_payment_id      = $tr_rjct->{payment_id};
						$rjct_currency        = $tr_rjct->{currency};
						$rjct_check_amount    = $tr_rjct->{check_amount};
						$rjct_reason_code     = $tr_rjct->{reason_code};
						$rjct_business_reason = $tr_rjct->{business_reason};
					}
					else {
						next;
					}

					$writer->startTag('TxInfAndSts');
					$writer->dataElement( 'OrgnlEndToEndId', $rjct_payment_id );
					$writer->dataElement( 'TxSts',           $rjct_status );
					$writer->startTag('StsRsnInf');
					$writer->startTag('Rsn');
					$writer->dataElement( 'Cd', $rjct_reason_code );
					$writer->endTag('Rsn');
					$writer->dataElement( 'AddtlInf', $rjct_business_reason );
					$writer->endTag('StsRsnInf');
					$writer->startTag('OrgnlTxRef');
					$writer->startTag('Amt');
					my $attr_info =
						"\n            <InstdAmt Ccy=\"$rjct_currency\">$rjct_check_amount</InstdAmt>\n          ";
					$writer->raw($attr_info);
					$writer->endTag('Amt');
					$writer->dataElement( 'ReqdExctnDt', $tr_rjct->{check_date} );
					$writer->endTag('OrgnlTxRef');

					$writer->endTag('TxInfAndSts');
				}
			}
			$writer->endTag('OrgnlPmtInfAndSts');
		}
	}
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
	my $processdate = "$year-$month-${dayOfMonth}T$hour:$minute:$second";
	$processdate =~ s/\s//g;    #strip out white space if introduced by Tidy's reformatting of the code

	return $processdate;
}

# this sub "list-ifies" complex data structures using a mix of hashes and arrays
sub fake_force_array {
	my $tree = shift;           # pass in $rec

	if ( ref $tree ) {
		if ( 'HASH' eq ref($tree) ) {
			if ( not %$tree ) {
				# empty hash
				return '';
			}

			foreach my $k ( keys %$tree ) {
				if ( ref $tree->{$k} ) {
					if ( 'ARRAY' eq ref $tree->{$k} ) {
						$tree->{$k} = fake_force_array( $tree->{$k} );
					}
					else {
						$tree->{$k} = fake_force_array( [ $tree->{$k} ] );
					}
				}
				else {
					$tree->{$k} = [ $tree->{$k} ];
				}
			}
		}
		elsif ( 'ARRAY' eq ref($tree) ) {
			foreach my $i ( 0 .. $#$tree ) {
				$tree->[$i] = fake_force_array( $tree->[$i] );
			}
		}
		else {
			die "Unknown ref type:\n" . Dumper($tree);
		}
	}
	# else, leave it alone

	return $tree;
}

1;
