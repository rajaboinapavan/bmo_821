package DocComp;

use strict;
use warnings;

use lib "$ENV{CCS_RESOURCE}";

use lib_CCS(
	GPD       => '3.00',
	JEF       => '1.00',
	JobEngine => '1.00',
);

use base qw(JobEngine_Render);
use Markup::Common;

################################################################################

use Data::Dumper;
$Data::Dumper::Indent   = 1;
$Data::Dumper::Sortkeys = 1;

################################################################################

use GPD;
use JobEngine;
use CcsCommon;
use Kaboom;
use Markup::Common;
use File::Copy;
use Sort::GPD;
use Time::localtime;
use AardvarkBilling;

use File::Basename;

use lib $ENV{'CCS_RESOURCE'} . '/Global/Std';

use Spreadsheet::WriteExcel;

# Global variable
my ( $rundate, $zipdate ) = _timestamp();

#------------------------------------------------------
# Subroutine: Init Render
#	Initialise rendering before the main loop
#------------------------------------------------------
sub init_render {
	my ( $this, $jobbag ) = @_;

	#$jobbag->{process_date} = $process_date;

	$this->SUPER::init_render($jobbag);

	my $streams = $this->{job}->get_stream_details();

	# Perform any manipulations\initialisations on the streams that may be required. In
	# this case, turning on barcodes and setting the master codeline position
	for my $stream_key ( keys %$streams ) {

		# this will be used later in the doc comp post process to find the stream name for a product
		# to get the laser and mail special instructions into the adm.xml because we get stream details from
		# one job bag and load the job to a different job bag
		( my $no_gpd_ext = $streams->{$stream_key}{stream}{name} ) =~ s/\.gpd//i;
		$jobbag->{stream_product_number}{$no_gpd_ext}{product_number} = $streams->{$stream_key}{stream}{prod_number};

		stream_setup( $streams->{$stream_key} );

	}

	for my $stream_key ( keys %{ $this->{job}{streamer}{ass_object}{data}{setups} } ) {

		if ( $stream_key =~ /UPS|FEDEX/i ) {

			for my $paper_stock_key (
				keys %{ $this->{job}{streamer}{ass_object}{data}{setups}{$stream_key}{declare_stock} } )
			{
				#Batch header page stock - '001CD80035'

				if (
					$this->{job}{streamer}{ass_object}{data}{setups}{$stream_key}{declare_stock}{$paper_stock_key}{name}
					=~ /White/i )
				{
					$jobbag->{white_sheet}{key} = $paper_stock_key;
					last;
				}
			}
		}
	}
	$jobbag->{environment} = CcsCommon::get_env();
	return;
}

#------------------------------------------------------
# Subroutine: Render
#	Render a data set
#	Note: to process a small amount of sets in test mode,
#		use --data_set_from and --data_set_to in proc_test.ini
#------------------------------------------------------

sub render {
	my ( $this, $set, $jobbag ) = @_;

	return undef if not $this->{job};

	my $render_errors;
	my $stream;
	my $sheet_cnt;
	my $processed = 0;
	my $filename =
		$set->get( xpath => 'File_Information/File_Name', must_exist => 0 );  # || fileparse( $jobbag->{__data}{name} );

	my $sp_handling = $set->get( xpath => 'Payer/Special_Handling_Code', must_exist => 0 ) || '';

	my $formatted_companyname = $set->get('File_Information/Company_Name');

	my $dom_code = $set->get( xpath => 'Addressee/Country', must_exist => 0 ) || 'USA';

	my $pbc = $set->get( xpath => 'CASS/pbc', must_exist => 0 ) || '';

	my $delivery_method =
		$set->get( xpath => 'File_Information/Courier_Information/Courier_Option', must_exist => 0 ) || 'usps';

	my $streams = $this->{job}->get_stream_details();

	###  WR-483 skip  dup check sets
	my $check_no = $set->get('Check_Data/Check_Number');
	$check_no =~ s/\s//g;
	my $clear_set = 0;

	if ( defined $jobbag->{'Duplicate_checks'} ) {

		foreach my $dup_no ( @{ $jobbag->{'Duplicate_checks'} } ) {
			if ( $dup_no eq $check_no ) {
				print "\n*** !!! Set has duplicate Check Number $check_no\n";
				$clear_set = 1;
			}
		}
	}

	$set->destination_stream_id();
	$render_errors = $this->SUPER::render( $set, $jobbag );
	dump_errors( $jobbag, $render_errors ) if ($render_errors);
	$sheet_cnt = get_cur_num_sheets_in_set;

	if ( !$jobbag->{__run_params}{options}{po_sample_mode} ) {
		$this->_positive_pay_hash( $filename, $jobbag, $set );
	}

	for my $stream_key ( sort keys %$streams ) {    # sorted ascendingly by stream name
		last if ($processed);

		my $gpd_name = $this->{job}{streamer}{ass_object}{data}{setups}{$stream_key}{new_gpd};
		$stream = $streams->{$stream_key};

		##-----------------------------------------
		# With Special Handling Code (01, 02 or 03)
		##-----------------------------------------
		if ( $sp_handling and $sp_handling =~ /^(01|02|03)$/ ) {

			# FedEx stream
			if ( $sp_handling =~ /^02$/ and $delivery_method =~ /FEDEX/i and $stream_key =~ /_FEDEX_/i ) {

				$this->_UPS_FedEx_render( $sp_handling, $filename, $gpd_name, $jobbag, $set, $stream );

				# set tag for address file
				$this->_add_FedEx_set_tag( $jobbag, $set );

				$processed = 1;
			}
			# FedExBulk stream
			elsif ( $sp_handling =~ /^(01|03)$/ and $delivery_method =~ /FEDEX/i and $stream_key =~ /_FEDEXBulk_/i ) {

				$this->_UPS_FedEx_render( $sp_handling, $filename, $gpd_name, $jobbag, $set, $stream );

				$this->_add_FedEx_set_tag( $jobbag, $set );

				$processed = 1;
			}
			# UPS stream
			elsif ( $sp_handling =~ /^02$/ and $delivery_method =~ /UPS/i and $stream_key =~ /_UPS_/i ) {

				$this->_UPS_FedEx_render( $sp_handling, $filename, $gpd_name, $jobbag, $set, $stream );

				# set tag for address file
				$this->_add_UPS_set_tag( $jobbag, $set );

				$processed = 1;
			}
			# UPSBulk stream
			elsif ( $sp_handling =~ /^(01|03)$/ and $delivery_method =~ /UPS/i and $stream_key =~ /_UPSBulk_/i ) {

				$this->_UPS_FedEx_render( $sp_handling, $filename, $gpd_name, $jobbag, $set, $stream );

				$this->_add_UPS_set_tag( $jobbag, $set );

				$processed = 1;
			}
			else {
				next;
			}
		}

		# -----------------------------------------------
		# No Special Handling
		# -----------------------------------------------
		else {
			# ---------------
			# Foreign stream
			# ---------------
			if ( $dom_code !~ /^(USA|US)$/ ) {

				if ( $delivery_method =~ /usps/i and $stream_key =~ /_FOR|FS/i ) {

					if ( $sheet_cnt >= 10 and $stream_key =~ /FOR_Lg/i ) {
						use_gpd $stream->{gpd};
						$jobbag->{stream}{$gpd_name}{count} += 1;
						$jobbag->{stream}{$gpd_name}{sort_status} = $stream->{stream}{sort_status};

						# Set tags for to be used for check database and Comm Center
						$this->_add_check_and_billing_set_tags( $filename, $set, $jobbag );

						$processed = 1;
					}
					elsif ( $sheet_cnt <= 9 and $sheet_cnt >= 6 and $stream_key =~ /FOR_Md/i ) {
						use_gpd $stream->{gpd};
						$jobbag->{stream}{$gpd_name}{count} += 1;
						$jobbag->{stream}{$gpd_name}{sort_status} = $stream->{stream}{sort_status};

						# Set tags for to be used for check database and Comm Center
						$this->_add_check_and_billing_set_tags( $filename, $set, $jobbag );

						$processed = 1;
					}
					elsif ( $sheet_cnt <= 5 and $sheet_cnt >= 2 and $stream_key =~ /FOR_Sm/i ) {
						use_gpd $stream->{gpd};
						$jobbag->{stream}{$gpd_name}{count} += 1;
						$jobbag->{stream}{$gpd_name}{sort_status} = $stream->{stream}{sort_status};

						# Set tags for to be used for check database and Comm Center
						$this->_add_check_and_billing_set_tags( $filename, $set, $jobbag );

						$processed = 1;
					}
					elsif ( $sheet_cnt == 1 and $stream_key =~ /FS_Sm/i ) {
						use_gpd $stream->{gpd};
						$jobbag->{stream}{$gpd_name}{count} += 1;
						$jobbag->{stream}{$gpd_name}{sort_status} = $stream->{stream}{sort_status};

						# Set tags for to be used for check database and Comm Center
						$this->_add_check_and_billing_set_tags( $filename, $set, $jobbag );

						$processed = 1;
					}
					else {

						next;
					}
				}
			}
			else {    # Domestic stream

				if ( $delivery_method =~ /usps/i and $stream_key =~ /_DOM|_DS/i ) {

					# dom large envelope
					if ( $sheet_cnt >= 10 and $stream_key =~ /DOM_Lg/i ) {
						use_gpd $stream->{gpd};
						$jobbag->{stream}{$gpd_name}{count} += 1;
						$jobbag->{stream}{$gpd_name}{sort_status} = $stream->{stream}{sort_status};

						# Set tags for to be used for check database and Comm Center
						$this->_add_check_and_billing_set_tags( $filename, $set, $jobbag );

						$processed = 1;
					}
					# dom medium envelope
					elsif ( $sheet_cnt <= 9 and $sheet_cnt >= 6 and $stream_key =~ /DOM_Md/i ) {
						use_gpd $stream->{gpd};
						$jobbag->{stream}{$gpd_name}{count} += 1;
						$jobbag->{stream}{$gpd_name}{sort_status} = $stream->{stream}{sort_status};

						# Set tags for to be used for check database and Comm Center
						$this->_add_check_and_billing_set_tags( $filename, $set, $jobbag );

						$processed = 1;
					}
					# dom small envelope
					elsif ( $sheet_cnt <= 5 and $sheet_cnt >= 2 and $stream_key =~ /DOM_Sm/i ) {
						use_gpd $stream->{gpd};
						$jobbag->{stream}{$gpd_name}{count} += 1;
						$jobbag->{stream}{$gpd_name}{sort_status} = $stream->{stream}{sort_status};

						# Set tags for to be used for check database and Comm Center
						$this->_add_check_and_billing_set_tags( $filename, $set, $jobbag );

						$processed = 1;
					}
					# dom small envelope - single sheet
					elsif ( $sheet_cnt == 1 and $stream_key =~ /DS_Sm/i ) {
						use_gpd $stream->{gpd};
						$jobbag->{stream}{$gpd_name}{count} += 1;
						$jobbag->{stream}{$gpd_name}{sort_status} = $stream->{stream}{sort_status};

						# Set tags for to be used for check database and Comm Center
						$this->_add_check_and_billing_set_tags( $filename, $set, $jobbag );

						$processed = 1;
					}
					else {
						next;
					}
				}    # end - domestic stream

				else {
					next;
				}
			}    # end regular sets - domestic
		}    # end - special handling
	}

	if ( !$processed ) {
		Utils::JEF_Exception::terminate(
			      "\nSet no: $set->{set_no} was not processed.  Escalate to CIC programmer for investigation."
				. "\nName 		: $set->get('Addressee/Address_Line_1')" );
	}
	else {
		if ( $clear_set == 1 ) {    # WR-483
			clear_set;
		}
		else {
			# WR-495 workaround for a bug involving start_reverse and duplex
			# with respect to the GPD function get_cur_num_imaged_pages_in_set
			my $imaged_pages;

			for my $sheet ( 1 .. get_cur_num_sheets_in_set ) {
				for my $side ( 'FRONT', 'REVERSE' ) {
					eval {
						local $SIG{__DIE__} = undef;
						set_current_sheet $sheet, $side;

						if ( not get_cur_page_is_blank ) {
							$imaged_pages++;
						}
					};
				}
			}

			add_set_tags( SLD_FollowerImages => $imaged_pages - 1 );

			# WR565 -- added the following set tags that will be used to generate PDF images only for Holland accounts
			add_set_tags(
				'party_id'       => $set->get( xpath => 'File_Information/Party_ID' ),
				'tran_id'        => $set->get( xpath => 'File_Information/Tran_ID' ),
				'pdf_image_flag' => $set->get( xpath => 'File_Information/PDF_Image_Flag', must_exist => 0 ) || 0,
			);

			emit_set;
		}
	}

	return 1;
}

#------------------------------------------------------
# Subroutine: Finalise Render
#	Finalise Render
#	Close off all the GPDs.
#------------------------------------------------------
sub finalise_render {
	my ( $this, $jobbag ) = @_;

	# $jobbag->{streams} is used by the duplicate check database module CheckUniqueVerify
	my $streams = $this->{job}->get_stream_details();
	while ( my ( $stream, $value ) = each %{$streams} ) {
		( my $stream_name = $streams->{$stream}{stream}{name} ) =~ s/\.gpd$//i;
		push @{ $jobbag->{streams} }, $stream_name;
	}
	$this->SUPER::finalise_render($jobbag);

	# sort the UPS and Fedex streams
	foreach my $gpd ( glob('145BM0100_*.gpd') ) {
		my $noext_gpd = ( split( /\./, $gpd ) )[0];

		if ( $gpd !~ /UPS|FEDEX/i
			&& ( $jobbag->{stream}{$noext_gpd}{sort_status} eq 'to_be_sorted' ) )
		{
			Utilities::batch_breaks($gpd);
		}
	}

	return 1;
}

sub init_streams {
	my ($streams) = @_;
	my $this = shift;
	return 1;
}

sub stream_setup {
	my ($stream) = @_;

	# Perform any manipulations\initialisations on the streams that may be required.
	# In this case, it is turning on barcodes, setting the OCR position, etc.
	my $s_key    = $stream->{'key'};
	my $workflow = $stream->{'workflow'};

	my $stock = ( values %{ $stream->{'stocks'} } )[0];
	next if ( $stock->{xsize} == 0 or $stock->{ysize} == 0 );

	my $envelope;
	eval {
		local ( $SIG{__DIE__} ) = undef;
		$envelope = ( values %{ $stream->{'envelopes'} } )[0]{size};
	};
	if ($@) {
		$envelope = '#10';
		print " Warn: can't determine envelope size for $s_key ... default to envelope $envelope.\n";
	}

	my $bc_preset = JobEngine::StreamerPlugin->get_barcode_preset( $stock, $envelope );

	use_gpd $stream->{gpd};

	if (   $workflow->{'mail_process_machine'} > 0
		or $workflow->{'mail_process_hand'} > 0
		or $workflow->{'dispatch'} > 0 )
	{
		if ( $envelope =~ /#10/ ) {
			sheet_marks
				do_ocr     => 1,
				ocr_orient => 0,
				ocr_font   => 'OCRA+10',
				ocr_x      => 9.4,
				ocr_y      => 3.5,
				do_bc      => 1,
				bc_preset  => $bc_preset,
				bc_x       => 21.5,
				bc_y       => 1.1,
				bc_orient  => 270;
		}
		elsif ( $envelope =~ /6x9.5/i ) {
			sheet_marks
				do_ocr     => 1,
				ocr_orient => 0,
				ocr_font   => 'OCRA+10',
				ocr_x      => 9.4,
				ocr_y      => 3.5,
				do_bc      => 1,
				bc_preset  => $bc_preset,
				bc_x       => 21.5,
				bc_y       => 1.1,
				bc_orient  => 270;
		}
		elsif ( $envelope =~ /9x12/i ) {
			sheet_marks
				do_ocr     => 1,
				ocr_orient => 0,
				ocr_font   => 'OCRA+10',
				ocr_x      => 9.4,
				ocr_y      => 3.5,
				do_bc      => 1,
				bc_preset  => $bc_preset,
				bc_x       => 13.3,
				bc_y       => 1.1,
				bc_orient  => 0;
		}
		else {
			Utils::JEF_Exception::terminate("Envelope size, $envelope is not yet supported");
		}
	}
	else {
		# do not put sheet marks
	}
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
	my $zdate      = "${year}${month}${dayOfMonth}${hour}${minute}${second}";

	my $rdate = "${year}-${month}-${dayOfMonth}";

	return ( $rdate, $zdate );

}

sub _add_check_and_billing_set_tags {
	my ( $this, $filename, $set, $jobbag ) = @_;

	my $unpadded_checkno = $set->get('Check_Data/Check_Number');
	$unpadded_checkno =~ s/\s//g;

	my $unpadded_acctno = $set->get('Check_Data/Account_Number');
	$unpadded_acctno =~ s/\s//g;

	my $datestamp = '';
	if ( $filename =~ /(.*)PAIN001\.((VEND|NONVEND)\.)?(\d{4})(\d{2})(\d{2}).*\./ ) {
		$datestamp = "$4-$5-$6";
	}

	# set tag for sorting streams
	add_set_tags( sort_key => get_set_weight );

	if ( !$jobbag->{__run_params}{options}{po_sample_mode} ) {

		# check set tags use for check database
		add_set_tags(
			check_number    => $unpadded_checkno,
			transit_number  => $set->get('Check_Data/Routing_Number'),
			account_number  => $unpadded_acctno,
			amount          => $set->get('Check_Data/Check_Amount'),
			settlement_date => $set->get('Check_Data/Check_Date'),
			payment_country => $set->get( xpath => 'Addressee/Country', must_exist => 0 ) || 'USA',
			currency        => 'USD',
			misc_check_info => $set->get( xpath => 'Check_Data/Memo', must_exist => 0 ) || '',
			#set tags for monthly billing report
			SLD_AccountNumber => $unpadded_acctno,
			SLD_FileName      => $filename,
			SLD_FileDate      => $datestamp,
		);

	}
	return 1;
}

sub _use_batch_address {
	my ( $this, $set, $sp_handling ) = @_;
	my $PO_address_ind = 0;
	my @addrlines;
	my $city;
	my $state;
	my $zip;

	if ( $sp_handling =~ /^01$/ ) {

		push @addrlines, $set->get('Payer/Name') || '';
		push @addrlines, $set->get('Payer/Address_1');
		$city  = $set->get('Payer/City')  || '';
		$state = $set->get('Payer/State') || '';
		$zip   = $set->get('Payer/Zip')   || '';
		push @addrlines, join( ' ', $city, $state, $zip );
		@addrlines = grep { !/^\s*$/ } @addrlines;

	}
	elsif ( $sp_handling =~ /^03$/ ) {    # special handling code = 03

		push @addrlines, $set->get('Payer/Special_Handling_Address/Name')      || '';
		push @addrlines, $set->get('Payer/Special_Handling_Address/Attention') || '';
		push @addrlines, $set->get('Payer/Special_Handling_Address/Address')   || '';
		$city  = $set->get('Payer/Special_Handling_Address/City')     || '';
		$state = $set->get('Payer/Special_Handling_Address/State')    || '';
		$zip   = $set->get('Payer/Special_Handling_Address/Zip_Code') || '';
		push @addrlines, join( ' ', $city, $state, $zip );
		@addrlines = grep { !/^\s*$/ } @addrlines;

	}

	return (@addrlines);
}

sub dump_errors {
	my ( $jobbag, $errors ) = @_;
	if (@$errors) {

		if ( $jobbag->{__run_params}{options}{po_sample_mode} ) {    #or $jobbag->{__run_params}{options}{test_run} ) {
			return;
		}
		else {
			print Dumper('###################################  Errors - Begin  ###################################');
			print Dumper ($errors);
			print Dumper('###################################  Errors - End    ###################################');
			Utils::JEF_Exception::terminate(
				"\n########## Failed due to the render error or data error specified above.\n");
		}
	}
	return 1;
}

sub _UPS_FedEx_render {
	my ( $this, $sp_handling, $filename, $gpd_name, $jobbag, $set, $stream ) = @_;

	my $courier_account_number = $set->get('File_Information/Courier_Information/Account_Number');
	$courier_account_number =~ s/^\s*|\s*$//g;

	# create dispatch:product tag value
	# including special handling code 03, which gets the data from enCompass
	my $batch_acct_key = '';

	if ( $sp_handling =~ /^01/ ) {
		# WR608 - added <PmtInfId> aka <Payer/TransactionID> to the sort key, because
		# there were couple of cases where the addresses for 2 different
		# <PmtInfId> have been different
		$batch_acct_key = sprintf '%010s%02d%038s',
			$courier_account_number,
			$sp_handling,
			$set->get('Payer/TransactionID');
	}
	else {
		$batch_acct_key = sprintf '%010s%02d', $courier_account_number, $sp_handling;
	}

	if ( !$batch_acct_key ) {
		Utils::JEF_Exception::terminate("dispatch:product tag is empty..");
	}

	# add the dispatch tags
	my %dispatch;
	foreach my $key qw(address_attention
		address_attention2
		address_company
		address_address1
		address_address2
		address_address3
		address_address4
		address_suburb
		address_state
		address_postcode
		address_country
		address_phonenumber
		reference_number) {
		$dispatch{$key} = '-';
		}

		# courier_type is a mandatory field (ref: AdmXml.html)
		# allowable values from DB are: Executive, Internal, Standard, VIP, NULL
		$dispatch{courier_type} = 'Internal';
	$dispatch{product}          = $batch_acct_key;
	Markup::Common::add_set_tags_dispatch( \%dispatch );

	$jobbag->{dispatch}{account}{$batch_acct_key}{count} += 1;

	# Set tags for to be used for check database and billing
	$this->_add_check_and_billing_set_tags( $filename, $set, $jobbag );

	my @billing_addrlines;
	my $city;
	my $state;
	my $zip;

	push @billing_addrlines, $set->get('File_Information/Courier_Information/Bill_to_Name') || '';
	push @billing_addrlines, $set->get('File_Information/Courier_Information/Bill_to_Address/Street_Address') || '';
	$city  = $set->get('File_Information/Courier_Information/Bill_to_Address/City')     || '';
	$state = $set->get('File_Information/Courier_Information/Bill_to_Address/State')    || '';
	$zip   = $set->get('File_Information/Courier_Information/Bill_to_Address/Zip_Code') || '';
	push @billing_addrlines, join( ' ', $city, $state, $zip );
	@billing_addrlines = grep { !/^\s*$/ } @billing_addrlines;

	my @addrlines = $this->_use_batch_address( $set, $sp_handling );

	use_gpd $stream->{gpd};

	#Put a batch header sheet per batch sort key
	if ( $jobbag->{dispatch}{account}{$batch_acct_key}{count} == 1 ) {

		start_batch_head $jobbag->{white_sheet}{key}, $batch_acct_key;

		put 'Courier Bill to Account Number: '
			. $courier_account_number,
			3.5,
			4, 'ArialMT+10';
		put 'Courier Bill to Name and Address:', 3.5, 5, 'ArialMT+10';
		list \@billing_addrlines, 4.2, 5.6, 'ArialMT+10', 0.42;

		if ( $sp_handling =~ /^(01|03)$/ ) {
			put 'Shipping Address Name and Address:', 3.5, 8, 'ArialMT+20';
			list \@addrlines, 4.2, 9.0, 'ArialMT+20', 0.60;
		}
		else {
			put 'Shipping Address Name and Address is Address on Record.', 3.5, 8, 'ArialMT+20';
		}

		end_batch_head;
	}

	return 1;
}

sub _add_UPS_set_tag {
	my ( $this, $jobbag, $set ) = @_;
	if ( !$jobbag->{__run_params}{options}{po_sample_mode} ) {
		my $updated_field;

		#CustomerID
		my $addr_label_fields = ',';

		#  Company Name
		if ( $set->get('Payer/Special_Handling_Code') =~ /01/ ) {
			$updated_field = $set->get('Payer/Name') ? _remove_comma( $set->get('Payer/Name') ) : '';
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /02/ ) {
			$updated_field =
				$set->get('Addressee/Address_Line_1')
				? _remove_comma( $set->get('Addressee/Address_Line_1') )
				: '';
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /03/ ) {
			$updated_field =
				$set->get('Payer/Special_Handling_Address/Name')
				? _remove_comma( $set->get('Payer/Special_Handling_Address/Name') )
				: '';
		}

		$addr_label_fields .= $updated_field . ',';

		#  Attention:
		$addr_label_fields .= ',';

		#  Address1
		if ( $set->get('Payer/Special_Handling_Code') =~ /01/ ) {
			$updated_field = $set->get('Payer/Address_1') ? _remove_comma( $set->get('Payer/Address_1') ) : '';
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /02/ ) {
			$updated_field =
				$set->get('Addressee/Address_Line_2')
				? _remove_comma( $set->get('Addressee/Address_Line_2') )
				: '';
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /03/ ) {
			$updated_field =
				$set->get('Payer/Special_Handling_Address/Address')
				? _remove_comma( $set->get('Payer/Special_Handling_Address/Address') )
				: '';
		}
		$addr_label_fields .= $updated_field . ',';

		#  Address2:
		if ( $set->get('Payer/Special_Handling_Code') =~ /02/ ) {
			$updated_field =
				$set->get('Addressee/Address_Line_3')
				? _remove_comma( $set->get('Addressee/Address_Line_3') )
				: '';
			$addr_label_fields .= $updated_field . ',';
		}
		else {
			$addr_label_fields .= ',';
		}

		#Address3 - leave blank
		$addr_label_fields .= ',';

		if ( $set->get('Payer/Special_Handling_Code') =~ /01/ ) {

			#City
			$addr_label_fields .= $set->get('Payer/City') . ',';

			#State
			$addr_label_fields .= $set->get('Payer/State') . ',';

			#Ship To - Postal Code
			$addr_label_fields .= $set->get('Payer/Zip') . ',';
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /02/ ) {
			# City
			$addr_label_fields .= $set->get('Addressee/City') . ',';

			# State
			$addr_label_fields .= $set->get('Addressee/State') . ',';

			# Zipcode
			$addr_label_fields .= $set->get('Addressee/ZipCode') . ',';
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /03/ ) {
			# City
			$addr_label_fields .= $set->get('Payer/Special_Handling_Address/City') . ',';

			# State
			$addr_label_fields .= $set->get('Payer/Special_Handling_Address/State') . ',';

			# Zipcode
			$addr_label_fields .= $set->get('Payer/Special_Handling_Address/Zip_Code') . ',';
		}

		# email, phone
		$addr_label_fields .= ',,';

		# reference1
		$addr_label_fields .= substr( $set->get('File_Information/Courier_Information/Bill_to_Name'), 0, 35 ) . ',';

		# reference2, weight, service,
		$addr_label_fields .= ',,1DA,';

		# packageType,BillTransportationTo
		$addr_label_fields .= 'EE,TP,';

		#bill_to_name
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Bill_to_Name') . ',';

		#bill_to_address
		$updated_field =
			$set->get('File_Information/Courier_Information/Bill_to_Address/Street_Address')
			? _remove_comma( $set->get('File_Information/Courier_Information/Bill_to_Address/Street_Address') )
			: '';
		$addr_label_fields .= $updated_field . ',';

		#bill_to_country
		$addr_label_fields .= 'US,';

		#bill_to_zip
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Bill_to_Address/Zip_Code') . ',';

		#bill_to_city
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Bill_to_Address/City') . ',';

		#bill_to_state
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Bill_to_Address/State') . ',';

		#bill_to_account
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Account_Number') . ',';

		add_set_tags( 'addresslabel' => $addr_label_fields, );
	}
	return 1;
}

sub _add_FedEx_set_tag {
	my ( $this, $jobbag, $set ) = @_;
	if ( !$jobbag->{__run_params}{options}{po_sample_mode} ) {
		my $addr_label_fields;

		# COMPANY
		$addr_label_fields = $set->get('File_Information/Company_Name') . "\t";

		# CLIENT
		$addr_label_fields .= 'BMO-US' . "\t";

		# BILL TO ACCOUNT NUMBER
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Account_Number') . "\t";

		# NAME
		if ( $set->get('Payer/Special_Handling_Code') =~ /01/ ) {
			$addr_label_fields .= $set->get('Payer/Name') . "\t";
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /02/ ) {
			$addr_label_fields .= $set->get('Addressee/Address_Line_1') . "\t";
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /03/ ) {
			$addr_label_fields .= $set->get('Payer/Special_Handling_Address/Name') . "\t";
		}

		# EMPTY CELL
		$addr_label_fields .= "\t";

		# ADDRESS 1
		if ( $set->get('Payer/Special_Handling_Code') =~ /01/ ) {
			$addr_label_fields .= $set->get('Payer/Address_1') . "\t";
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /02/ ) {
			$addr_label_fields .= $set->get('Addressee/Address_Line_2') . "\t";
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /03/ ) {
			$addr_label_fields .= $set->get('Payer/Special_Handling_Address/Address') . "\t";
		}

		# ADDRESS 2 OR EMPTY CELL
		if ( $set->get('Payer/Special_Handling_Code') =~ /02/ ) {
			$addr_label_fields .= $set->get('Addressee/Address_Line_3') . "\t";
		}
		else {
			$addr_label_fields .= "\t";
		}

		if ( $set->get('Payer/Special_Handling_Code') =~ /01/ ) {
			# CITY
			$addr_label_fields .= $set->get('Payer/City') . "\t";

			# STATE
			$addr_label_fields .= $set->get('Payer/State') . "\t";

			# ZIP
			$addr_label_fields .= $set->get('Payer/Zip') . "\t";
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /02/ ) {
			# CITY
			$addr_label_fields .= $set->get('Addressee/City') . "\t";

			# STATE
			$addr_label_fields .= $set->get('Addressee/State') . "\t";

			# ZIP
			$addr_label_fields .= $set->get('Addressee/ZipCode') . "\t";
		}
		elsif ( $set->get('Payer/Special_Handling_Code') =~ /03/ ) {
			# CITY
			$addr_label_fields .= $set->get('Payer/Special_Handling_Address/City') . "\t";

			# STATE
			$addr_label_fields .= $set->get('Payer/Special_Handling_Address/State') . "\t";

			# ZIP
			$addr_label_fields .= $set->get('Payer/Special_Handling_Address/Zip_Code') . "\t";
		}

		# BILL TO NAME
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Bill_to_Name') . "\t";

		# BILL TO ADDRESS
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Bill_to_Address/Street_Address') . "\t";

		# EMPTY CELL
		$addr_label_fields .= "\t";

		# BILL TO CITY
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Bill_to_Address/City') . "\t";

		# BILL TO STATE
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Bill_to_Address/State') . "\t";

		# BILL TO ZIP CODE
		$addr_label_fields .= $set->get('File_Information/Courier_Information/Bill_to_Address/Zip_Code');

		add_set_tags( 'addresslabel' => $addr_label_fields, );

	}
	return 1;
}

sub _remove_comma {
	my ($fieldname) = @_;

	my $upd_field = $fieldname;

	$upd_field =~ s/, / /g;        #remove commas
	$upd_field =~ s/,/ /g;         #replace comma with a space
	$upd_field =~ s/\s{2,}/ /g;    #remove extra spaces

	return $upd_field;
}

sub _positive_pay_hash {
	my ( $this, $file_name, $jobbag, $set ) = @_;

	# WR 558
	# NONVEND	: T.COMSHARUS.10002148DC.PAIN001.NONVEND.20240222105435.N641882.XML
	# VEND		: T.COMSHARUS.10002148SV.PAIN001.VEND.20240222144730.N192708.XML
	# REGULAR	: T.COMSHARUS.HOLLANH2H.PAIN001.20240209134928.N576001.xml
	#( $t, $comsharus, $customer_id, $pain001, $filedate, $filetime, $serialnumber, $xml, $po, $file_ext )
	my ( $t, $comsharus, $customer_id, $pain001, $type, $filedate, $serialnumber, $id, $file_ext );
	if ( not exists $jobbag->{$file_name}{filedate} and not exists $jobbag->{$file_name}{filetime} ) {
		if ( $file_name =~ /\.(VEND|NONVEND)\./ ) {
			( $t, $comsharus, $customer_id, $pain001, $type, $filedate, $serialnumber, $id, $file_ext ) =
				split( /\./, $file_name );
		}
		else {
			( $t, $comsharus, $customer_id, $pain001, $filedate, $serialnumber, $id, $file_ext ) =
				split( /\./, $file_name );
		}

		$jobbag->{$file_name}{filedate} = $filedate;
		# retaining the $jobbag fieldname: 'filetime';
		$jobbag->{$file_name}{filetime} = $serialnumber;
	}

	my $routing_code;
	my $pospay_file;

	if ( $set->get('Check_Data/Routing_Number') =~ /071000288|071915580|125107888/ ) {
		$routing_code = '028';

	}
	elsif ( $set->get('Check_Data/Routing_Number') =~ /071025661/ ) {
		$routing_code = '029';
	}
	else {
		Utils::JEF_Exception::terminate(
"No routing_code available for $set->get('Check_Data/Routing_Number')\nUnable to create positive pay report\nNotify account manager\n"
		);
	}

	my $unpadded_acctno = $set->get('Check_Data/Account_Number');
	$unpadded_acctno =~ s/\s//g;

	my ( $chk_year, $chk_month, $chk_day ) = split( /-/, $set->get('Check_Data/Check_Date') );
	my $formatted_chkdate = $chk_month . $chk_day . substr( $chk_year, 2, 2 );
	my $formatted_chkpayee = substr( $set->get('Check_Data/Payee/Payee_Line_1'), 0, 128 );
	my $formatted_acctno =
		( length($unpadded_acctno) < 10 )
		? sprintf '%010d', $unpadded_acctno
		: $unpadded_acctno;
	my $cleaned_checkno = $set->get('Check_Data/Check_Number');
	$cleaned_checkno =~ s/^\s+|\s+$//g;
	my $formatted_checkno  = sprintf '%010s', $cleaned_checkno;
	my $set_chkamt_len     = 10;
	my $formatted_checkamt = $set->get('Check_Data/Check_Amount');
	$formatted_checkamt =~ s/\s|\.//g;
	$formatted_checkamt = "0" x ( $set_chkamt_len - length($formatted_checkamt) ) . $formatted_checkamt;

	my $row = 'C'
		. $routing_code . '00'
		. $formatted_acctno . ' ' . 'R' . 'A' . ' '
		. $formatted_checkno
		. $formatted_checkamt
		. $formatted_chkdate
		. ' ' x 20
		. $formatted_chkpayee;

	# logic to parse file_name is moved from here to start of this subroutine

	if ( $jobbag->{environment} !~ /production/i ) {
		if ( $set->get('Check_Data/Routing_Number') =~ /071000288|071915580|125107888/ ) {
			$pospay_file =
				  'COMPAYUS.CCSUSTEST.IDIRECTCK.'
				. $jobbag->{$file_name}{filedate} . '.'
				. $jobbag->{$file_name}{filetime}
				. '.ARP530R.txt';
		}
		elsif ( $set->get('Check_Data/Routing_Number') =~ /071025661/ ) {
			$pospay_file =
				  'COMPAYUS.CCSUS29TEST.IDIRECTCK.'
				. $jobbag->{$file_name}{filedate} . '.'
				. $jobbag->{$file_name}{filetime}
				. '.ARP530S.txt';
		}
	}
	else {    # in production
		if ( $set->get('Check_Data/Routing_Number') =~ /071000288|071915580|125107888/ ) {
			$pospay_file =
				  'COMPAYUS.CCSUS.IDIRECTCK.'
				. $jobbag->{$file_name}{filedate} . '.'
				. $jobbag->{$file_name}{filetime}
				. '.ARP50T8.txt';
		}
		elsif ( $set->get('Check_Data/Routing_Number') =~ /071025661/ ) {
			$pospay_file =
				  'COMPAYUS.CCSUS29.IDIRECTCK.'
				. $jobbag->{$file_name}{filedate} . '.'
				. $jobbag->{$file_name}{filetime}
				. '.ARP52ZW.txt';
		}
	}

	# to be used for positive pay report
	push @{ $jobbag->{positive_report_details}{$pospay_file} }, { 'record' => $row };

	# WR565
	add_set_tags( 'serial_number' => $jobbag->{$file_name}{filetime}, );

	return 1;
}    # end of _positive_pay_hash()

1;
