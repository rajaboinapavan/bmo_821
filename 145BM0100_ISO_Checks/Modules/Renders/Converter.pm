package Converter;

use 5.010;

use strict;
use warnings;

use lib "$ENV{CCS_RESOURCE}";
use lib_CCS(
	GPD => '3.00',
	JEF => '1.00',
	local =>
		[ 'Modules', 'Modules/Processors', 'Modules/BusinessRules', 'Modules/Renders', 'Modules/Utils', '../Common', ],
	others => [
		$ENV{'CCS_RESOURCE'} . '/Regional/NA/Toolkit/lib',
		$ENV{'CCS_RESOURCE'} . '/Regional/US/Finalist/5.10',
		$ENV{'CCS_RESOURCE'} . '/Global/Std',
	],
);

use base qw(GenericRendering);
use IO::File;
use Logger::Log;
################################################################################

use Cwd qw( cwd );
use Data::Dumper;
use Carp;

use Getopt::Long;
use File::Copy;
use File::Basename qw(dirname basename);
use Time::localtime;
use XML::Writer;

use Spreadsheet::WriteExcel;

# Global variables
my ( $rundate, $zipdate ) = _timestamp();
################################################################################

sub init_render {
	my ( $this, $jobbag ) = @_;

	$this->SUPER::init_render($jobbag);

	$this->{writer} = $this->init_writer($jobbag);

	# These options deal with Finalist's CASS procesing.
	if ( not( $this->{skipFinalist} || $this->{finalistStarted} || $ENV{SKIP_FINALIST} || $ENV{FAKE_FINALIST} ) ) {
		require Finalist;
		Cass::Start_PBC( cwd(), '' );
		$this->{finalistStarted}++;
	}

	return;
}

#------------------------------------------------------
# Subroutine: Render
#   Render a data set
#   Note: to process a small amount of sets in test mode,
#	   use --data_set_from and --data_set_to in proc_test.ini
#------------------------------------------------------
sub render {
	my ( $this, $set, $jobbag ) = @_;

	my $errors = $this->SUPER::render( $set, $jobbag );

	if ( !defined $jobbag->{total_rendered_sets} ) {
		$jobbag->{total_rendered_sets} = 0;
	}
	if ( !defined $jobbag->{accept_chk_amount} ) {
		$jobbag->{accept_chk_amount} = '0.00';
	}
	if ( !defined $jobbag->{reject_chk_amount} ) {
		$jobbag->{reject_chk_amount} = '0.00';
	}

	if ( $set->{payer_details} ) {

		my ( $status, $reason_code, $business_reason ) = $this->validate_set( $set, $jobbag );

		## WR577 initialize client reports if this is the first set
		my $filename = $set->{file_information}{file_name};
		$filename =~ s/\.ID\.XML/\.XML/i;

		my $formatted_companyname = $set->{file_information}{company_name};
		$formatted_companyname =~ s/\s/_/g;

		my $formatted_acctno = $set->{check_details}{account_number};
		$formatted_acctno =~ s/\s//g;
		$formatted_acctno =~ s/^\d{4}/XXXX/;

		if ( !$jobbag->{$filename}{zip_file} ) {
			# configure general details for client reports zip file
			$jobbag->{$filename}{zip_file} = $formatted_companyname . '_Reports_' . $zipdate . '.zip';
			$jobbag->{ $jobbag->{$filename}{zip_file} }{zip_password} = $set->{payer_details}{zipfile_password}
				if ( $set->{payer_details}{zipfile_password} );
			$jobbag->{ $jobbag->{$filename}{zip_file} }{email_address} =
				  $set->{payer_details}{email_username}
				. $set->{payer_details}{email_domain}
				. $set->{payer_details}{email_extension};
		}

		if ( !$jobbag->{$filename}{exception_file} ) {
			# exception summary report
			$jobbag->{$filename}{exception_file} = 'Exception_' . $filename . '.xls';

			push @{ $jobbag->{client_report_list}{ $jobbag->{$filename}{zip_file} } },
				{ 'exception' => $jobbag->{$filename}{exception_file}, };

			$jobbag->{ $jobbag->{$filename}{exception_file} }{company_name} =
				$set->{file_information}{company_name};
			$jobbag->{ $jobbag->{$filename}{exception_file} }{file_name} = $filename;

			$jobbag->{ $jobbag->{$filename}{exception_file} }{account_number} = $formatted_acctno;

			$jobbag->{file_information}{CreDtTm} =~ /^(.*)T/;
			$jobbag->{ $jobbag->{$filename}{exception_file} }{run_date} = $1;

			$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rejected}{count} = 0;
			$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rejected}{value} = 0.00

		}

		if ( !$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} ) {
			$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} =
				'Chq_register_BMO' . $filename . '_1_' . $formatted_acctno . '.xls';

			push @{ $jobbag->{client_report_list}{ $jobbag->{$filename}{zip_file} } },
				{ "report_${formatted_acctno}" =>
					$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file}, };

			$jobbag->{ $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} }{company_name} =
				$set->{file_information}{company_name};
			$jobbag->{ $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} }{file_name} =
				$jobbag->{$filename}{checkreg_file};
			$jobbag->{ $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} }{account_number} =
				$formatted_acctno;
			$jobbag->{ $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} }{check_date} =
				$set->{check_details}{check_date};

			$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{accp}{count} = 0;
			$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{accp}{value} = 0.00;
			$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rjct}{count} = 0;
			$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rjct}{value} = 0.00;
		}

		if ( !$jobbag->{$filename}{disbursement_summary} ) {
			$jobbag->{$filename}{disbursement_summary} = 'Dis_summ_BMO' . $filename . '_BMO_USD.xls';
			$jobbag->{ $jobbag->{$filename}{disbursement_summary} }{file_name} = $filename;
			$jobbag->{ $jobbag->{$filename}{disbursement_summary} }{company_name} =
				$set->{file_information}{company_name};
			$jobbag->{ $jobbag->{$filename}{disbursement_summary} }{check_date} = $set->{check_details}{check_date};

		}

		if ( $status && 'ACCP' eq $status ) {
			$this->{writer}->startTag('Pack');
			{
				$this->corropack_details( $this->{writer}, $set, $jobbag );
				$this->payer_details( $this->{writer}, $set->{payer_details}, $set->{file_information}->{file_name} );
				$this->addressee_details( $this->{writer}, $set->{addressee_details} );
				$this->remit_details( $this->{writer}, $set->{remit_details}, $set->{check_details}{table_type} );
				$this->check_data( $this->{writer}, $set->{check_details}, $jobbag );
				$this->file_information( $this->{writer}, $set->{file_information}, $jobbag );
				$this->workflow( $this->{writer}, $set );
				$this->acknowledgment_details( $this->{writer}, $set, $status, $reason_code, $business_reason );
			}
			$this->{writer}->endTag('Pack');

			$jobbag->{total_rendered_sets}++;

			# WR577
			$this->_check_register_hash( $filename, $jobbag, $set );    # these are the ACCP checks
		}
		else {
			$this->_rjct_register_hash( $filename, $jobbag, $set, $business_reason,
				$set->{check_details}{account_number} );                # these are the RJCT checks
		}

	}

	return;
}

sub file_information {
	my ( $this, $writer, $set ) = @_;

	my %nilable;

	$writer->startTag('File_Information');
	{

		$writer->dataElement( 'File_Name',        $set->{file_name} );
		$writer->dataElement( 'Company_Name',     $set->{company_name} );
		$writer->dataElement( 'Number_of_Checks', $set->{number_of_checks} );
		$writer->dataElement( 'Check_Total',      $set->{check_total} );
		$writer->dataElement( 'Party_ID',         $set->{party_id} );
		$writer->dataElement( 'Tran_ID',          $set->{tran_id} );
		$writer->dataElement( 'PDF_Image_Flag',   $set->{pdf_image_flag} ) if ( $set->{pdf_image_flag} );

		$writer->startTag('Courier_Information');
		{

			%nilable = (
				'Account_Number' => $set->{courier_account_number},
				'Bill_to_Name'   => $set->{courier_bill_to_name},
				'Courier_Option' => $set->{courier_option},
			);

			$this->_nilable( $writer, %nilable );

			$writer->startTag('Bill_to_Address');
			{

				%nilable = (
					'Street_Address' => $set->{courier_bill_to_street},
					'City'           => $set->{courier_bill_to_city},
					'State'          => $set->{courier_bill_to_state},
					'Zip_Code'       => $set->{courier_bill_to_zipcode},

				);

				$this->_nilable( $writer, %nilable );

			}
			$writer->endTag('Bill_to_Address');

		}
		$writer->endTag('Courier_Information');

	}
	$writer->endTag('File_Information');

	return 1;

}

sub payer_details {
	my ( $this, $writer, $set, $file_name ) = @_;

	my %nilable;

	$writer->startTag('Payer');
	{

		%nilable = ( 'Special_Handling_Code' => $set->{special_handling}, );

		$this->_nilable( $writer, %nilable );

		$writer->dataElement( 'TransactionID', $set->{transaction_id} );

		if ( defined( $set->{vendor_id} ) ) {
			$writer->dataElement( 'Vendor_ID', $set->{vendor_id} );
		}
		# WR 558 Vendor tag
		my $vendor = '';
		( undef, undef, $vendor, undef ) = ( $file_name =~ /(.*)(PAIN001\.)(VEND|NONVEND)(.*)/ )
			if ( $file_name =~ /\.(VEND|NONVEND)\./ );
		%nilable = ( 'Vendor' => $vendor );
		$this->_nilable( $writer, %nilable );

		$writer->dataElement( 'Name', $set->{name} );
		if ( defined( $set->{building_number} ) ) {
			$writer->dataElement( 'Address_1', $set->{building_number} . ' ' . $set->{street_name} );
		}
		else {
			$writer->dataElement( 'Address_1', $set->{street_name} );
		}
		$writer->dataElement( 'City',  $set->{city} );
		$writer->dataElement( 'State', $set->{state} );
		$writer->dataElement( 'Zip',   $set->{zip_code} );
		$writer->dataElement( 'Company_Email_Address',
			$set->{email_username} . $set->{email_domain} . $set->{email_extension} );
		$writer->dataElement( 'Zip_File_Password', $set->{zipfile_password} );

		$writer->startTag('Special_Handling_Address');
		{

			%nilable = (
				'Name'      => $set->{special_handling_name},
				'Attention' => $set->{special_handling_attention},
				'Address'   => $set->{special_handling_street_address},
				'City'      => $set->{special_handling_city},
				'State'     => $set->{special_handling_state},
				'Zip_Code'  => $set->{special_handling_zip_code},
			);

			$this->_nilable( $writer, %nilable );

		}
		$writer->endTag('Special_Handling_Address');

	}
	$writer->endTag('Payer');

	return 1;

}

sub check_data {
	my ( $this, $writer, $set, $jobbag ) = @_;

	my %nilable = (
		'Check_Amount'   => $set->{check_amount},
		'Check_Number'   => $set->{check_number},
		'Check_Date'     => $set->{check_date},
		'Memo'           => $set->{memo},
		'Account_Number' => $set->{account_number},
		'Routing_Number' => $set->{routing_number},
	);

	$writer->startTag('Check_Data');
	{
		# WR 576
		my $extra_address = 0;
		my $bank_address  = '';
		$bank_address .= $jobbag->{extra_options}{bank_address1}
			if ( $jobbag->{extra_options}{bank_address1} );

		for my $address (qw(bank_address2 bank_address3 bank_address4)) {
			if ( $set->{$address} ) {
				$bank_address .= '|' . $set->{$address};
				$extra_address = 1;
			}
		}

		if ($extra_address) {
			$writer->dataElement( 'Bank_Address', $bank_address );
		}

		$this->_nilable( $writer, %nilable );

		$writer->dataElement( 'Signature_Location', $set->{check_signature_graphic_dir} );
		$writer->dataElement( 'Signature_Filename', $set->{check_signature_graphic} );

		$writer->dataElement( 'Void_Text', $set->{void_after} );

		$writer->startTag('Payee');
		{
			$writer->dataElement( 'Payee_Line_1', $set->{name} );

			if ( defined( $set->{street_name} ) ) {
				if ( defined( $set->{building_number} ) ) {
					$writer->dataElement( 'Payee_Line_2', $set->{building_number} . ' ' . $set->{street_name} );
				}
				else {
					$writer->dataElement( 'Payee_Line_2', $set->{street_name} );
				}

				if ( defined( $set->{adr_lines} ) ) {
					# determine whether to use first or second element of array
					# if street name was missing ConverterBusinessRules assigns the first element
					# to StrtNm
					if ( $set->{street_name} eq @{ $set->{adr_lines} }[0] ) {
						if ( defined @{ $set->{adr_lines} }[1] ) {
							$writer->dataElement( 'Payee_Line_3', @{ $set->{adr_lines} }[1] );
						}
						else {
							%nilable = ( 'Payee_Line_3' => @{ $set->{adr_lines} }[1], );
							$this->_nilable( $writer, %nilable );
						}
					}
					else {
						$writer->dataElement( 'Payee_Line_3', @{ $set->{adr_lines} }[0] );
					}
				}
				else {
					%nilable = ( 'Payee_Line_3' => @{ $set->{adr_lines} }[0], );
					$this->_nilable( $writer, %nilable );
				}
			}
			elsif ( !defined( $set->{street_name} ) ) {
				$writer->dataElement( 'Payee_Line_2', @{ $set->{adr_lines} }[0] );

				if ( defined( @{ $set->{adr_lines} }[1] ) ) {
					$writer->dataElement( 'Payee_Line_3', @{ $set->{adr_lines} }[1] );
				}
				else {
					%nilable = ( 'Payee_Line_3' => @{ $set->{adr_lines} }[1], );
					$this->_nilable( $writer, %nilable );
				}
			}

			$writer->dataElement( 'Payee_Line_4', $set->{city} . ' ' . $set->{state} . ' ' . $set->{zip_code} );
		}
		$writer->endTag('Payee');

	}
	$writer->endTag('Check_Data');

	return 1;
}

sub remit_details {
	my ( $this, $writer, $set, $table_type ) = @_;

	$writer->startTag('Remittance_Advice');

	# WR 576
	$table_type //= 'Option 1';
	if ( $table_type && $table_type =~ /-/ ) {
		( $table_type, undef ) = split /-/, $table_type;
		$table_type =~ s/^\s+|\s+$//g;
	}
	$writer->dataElement( 'Remittance_Table_Type', $table_type );

	my %nilable = ( 'Remittance_Details' => $set->{remittance_info}, );

	foreach my $info ( @{ $set->{remittance_info} } ) {
		$writer->startTag('Remittance_Info');
		%nilable = ( 'Remittance_Details' => $info, );
		$this->_nilable( $writer, %nilable );
		$writer->endTag('Remittance_Info');
	}

	if ( $set->{remittance_table} ) {
		$writer->startTag('Remittance_Table');
		{

			foreach my $table ( @{ $set->{remittance_table} } ) {

				$writer->startTag('Remittance_Row');
				$table->{invoice_details} =~ s'(NOTE|DESC)//'' if ( $table->{invoice_details} );
				%nilable = (
					'Ref_ID'          => $table->{ref_id},             # WR 576
					'Ref_Type'        => $table->{ref_type},           # WR 576
					'Ref_Number'      => $table->{ref_number},
					'Ref_Date',       => $table->{ref_date},
					'Doc_Amount',     => $table->{doc_amount},
					'Disc_Amount',    => $table->{disc_amount},
					'Net_Amount'      => $table->{net_amount},
					'Invoice_Type',   => $table->{invoice_type},
					'Invoice_Details' => $table->{invoice_details},    # WR 576?
				);

				$this->_nilable( $writer, %nilable );

				$writer->endTag('Remittance_Row');
			}

		}
		$writer->endTag('Remittance_Table');
	}

	$writer->endTag('Remittance_Advice');

	return 1;

}

sub addressee_details {
	my ( $this, $writer, $set ) = @_;

	$writer->startTag('Addressee');
	{
		my %nilable = ( 'Country' => $set->{country}, );
		$this->_nilable( $writer, %nilable );

		$writer->dataElement( 'Address_Line_1', $set->{name} );

		if ( defined( $set->{street_name} ) ) {
			if ( defined( $set->{building_number} ) ) {
				$writer->dataElement( 'Address_Line_2', $set->{building_number} . ' ' . $set->{street_name} );
			}
			else {
				$writer->dataElement( 'Address_Line_2', $set->{street_name} );
			}

			if ( defined( $set->{adr_lines} ) ) {
				# determine whether to use first or second element of array
				# if street name was missing ConverterBusinessRules assigns the first element
				# to StrtNm
				if ( $set->{street_name} eq @{ $set->{adr_lines} }[0] ) {
					if ( defined @{ $set->{adr_lines} }[1] ) {
						$writer->dataElement( 'Address_Line_3', @{ $set->{adr_lines} }[1] );
					}
					else {
						%nilable = ( 'Address_Line_3' => @{ $set->{adr_lines} }[1], );
						$this->_nilable( $writer, %nilable );
					}
				}
				else {
					$writer->dataElement( 'Address_Line_3', @{ $set->{adr_lines} }[0] );
				}
			}
			else {
				%nilable = ( 'Address_Line_3' => @{ $set->{adr_lines} }[0], );
				$this->_nilable( $writer, %nilable );
			}
		}
		elsif ( !defined( $set->{street_name} ) ) {
			$writer->dataElement( 'Address_Line_2', @{ $set->{adr_lines} }[0] );

			if ( defined( @{ $set->{adr_lines} }[1] ) ) {
				$writer->dataElement( 'Address_Line_3', @{ $set->{adr_lines} }[1] );
			}
			else {
				%nilable = ( 'Address_Line_3' => @{ $set->{adr_lines} }[1], );
				$this->_nilable( $writer, %nilable );
			}
		}

		$writer->dataElement( 'City',    $set->{city} );
		$writer->dataElement( 'State',   $set->{state} );
		$writer->dataElement( 'ZipCode', $set->{zip_code} );

	}
	$writer->endTag('Addressee');

	# cass_address must be called after the address details have been added to CASS_ADDRESS_LINES

	$this->cass_address( $this->{writer}, $set );

	return 1;

}

sub cass_address {
	my ( $this, $writer, $set ) = @_;

	my @cass_address_lines;
	push @cass_address_lines, $set->{name};
	if ( defined( $set->{building_number} ) ) {
		push @cass_address_lines, $set->{building_number} . ' ' . $set->{street_name};
	}
	else {
		push @cass_address_lines, $set->{street_name};
	}
	push @cass_address_lines, $set->{city} . ' ' . $set->{state} . ' ' . $set->{zip_code};

	$writer->startTag('CASS');
	{

		my %address_properties = Cass::Correct_Address_No_GPD_Markup(
			address      => \@cass_address_lines,
			options      => '12N',
			standardMail => 0
		);

		foreach my $elem (
			'pbc',         'address1',        'address2', 'unit1',       'unit2',       'city',
			'state',       'zip',             'zip4',     'nonAddress1', 'nonAddress2', 'nonAddress3',
			'nonAddress4', 'mse',             'index1',   'index2',      'types',       'imb',
			'preimb',      'imbTrackingCode', 'route',    'deliveryPoint',
			)
		{
			$writer->dataElement( $elem, $address_properties{$elem} || '' );

		}

	}
	$writer->endTag('CASS');

	return 1;

}

sub workflow {
	my ( $this, $writer, $set ) = @_;

	$writer->startTag('CorrespondenceWorkflow');
	{
		# everything prints, the streaming and workflow logic is handled during doc comp
		$writer->dataElement( 'Print',                1 );
		$writer->dataElement( 'Mail_Process_Machine', 0 );
		$writer->dataElement( 'Lodge',                0 );
	}
	$writer->endTag('CorrespondenceWorkflow');

	return;
}

sub acknowledgment_details {
	my ( $this, $writer, $set, $status, $reason_code, $business_reason ) = @_;

	$writer->startTag('AcknowledgmentDetails');
	{
		# per set acknowledgment details for any necessary updates to the Acknowledgment file during doc comp
		# also use this as a vehicle for WR-536 to transmit information about the routing number and its source
		$writer->dataElement( 'Payment_ID',      $set->{check_details}{pmt_id} );
		$writer->dataElement( 'Status',          $status );
		$writer->dataElement( 'Reason_Code',     $reason_code );
		$writer->dataElement( 'Check_Amount',    $set->{check_details}{check_amount} );
		$writer->dataElement( 'Currency',        $set->{check_details}{check_currency} );
		$writer->dataElement( 'Transaction_ID',  $set->{payer_details}{transaction_id} );
		$writer->dataElement( 'Business_Reason', $business_reason );
		$writer->dataElement( 'Check_Number',    $set->{check_details}{check_number} );
		$writer->dataElement( 'CCS_EndtoEnd_ID', $set->{check_details}{ccs_endtoend_id} );
		$writer->dataElement( 'Check_Date',      $set->{check_details}{check_date} );

	}
	$writer->endTag('AcknowledgmentDetails');

	return;
}

sub corropack_details {
	my ( $this, $writer, $set, $jobbag ) = @_;

	$writer->startTag('CorrespondenceDetails');
	{

		if (   !$jobbag->{extra_options}{corropack_group}
			|| !$jobbag->{extra_options}{corropack_product}
			|| !$jobbag->{extra_options}{corropack_id} )
		{
			Utils::JEF_Exception::terminate(
'--corropack_group <string> or --corropack_product <string> or --corropack_id <string> were not part of the command line or Extra Arguments in the Aa Automated Job Details'
			);
		}

		$writer->dataElement( 'Correspondence_Pack_Id', $jobbag->{extra_options}{corropack_id} );
		$writer->dataElement( 'Group',                  $jobbag->{extra_options}{corropack_group} );
		$writer->dataElement( 'Product',                $jobbag->{extra_options}{corropack_product} );

	}
	$writer->endTag('CorrespondenceDetails');

	return 1;
}

sub _nilable {
	my ( $this, $writer, %nilable ) = @_;

	while ( my ( $node_name, $field_value ) = each %nilable ) {
		defined $field_value
			? $writer->dataElement( $node_name, $field_value )
			: $writer->emptyTag( $node_name, [ $this->{xsi_uri} => 'nil' ] => 'true' );
	}

	return 1;

}

#------------------------------------------------------
# Subroutine: Finalise Render
#   Finalise Render
#   Close off all the GPDs.
#------------------------------------------------------
sub finalise_render {
	my ( $this, $jobbag ) = @_;

	$this->SUPER::finalise_render($jobbag);

	$this->close_writer($jobbag);

	if ( $this->{finalistStarted} ) {
		Cass::End_PBC();
		$this->{finalistStarted} = undef;
	}

	return;
}

sub init_writer {
	my ( $this, $jobbag ) = @_;

	if ( @{ $jobbag->{__run_params}{data_files} } > 1 ) {
		Utils::JEF_Exception::terminate(
			"More than 1 file is being converted, we can currently only handle 1 at a time. The files are:\n"
				. Dumper @{ $jobbag->{__run_params}{data_files} } );
	}
	else {
		$jobbag->{'intermediary_po_xml'} = @{ $jobbag->{__run_params}{data_files} }[0] . '.po.xml';
	}

	open( $this->{po_xml_fh}, '>:encoding(UTF-8)', $jobbag->{'intermediary_po_xml'} )
		|| Utils::JEF_Exception::terminate(
		"Not able to open PO XML '$jobbag->{'intermediary_po_xml'}' for writing\n$!");

	$this->{xsi_uri} = "http://www.w3.org/2001/XMLSchema-instance";

	my $writer = XML::Writer->new(
		OUTPUT          => $this->{po_xml_fh},
		DATA_MODE       => 1,
		DATA_INDENT     => 2,
		NAMESPACES      => 1,
		PREFIX_MAP      => { $this->{xsi_uri} => 'xsi' },
		FORCED_NS_DECLS => [ $this->{xsi_uri} ]
	);
	$writer->xmlDecl("UTF-8");
	$writer->startTag('CCS');

	return $writer;
}

sub close_writer {
	my ( $this, $jobbag ) = @_;

	$this->{writer}->endTag('CCS');
	$this->{writer}->end();
	close $this->{po_xml_fh};

	return 1;
}

sub validate_set {
	# handles set/transaction level checks. Returns status if it fails; otherwise returns 0.
	my ( $this, $set, $jobbag ) = @_;

	my $status;
	my $reason_code;
	my $business_reason;

	# prior to going through the validation steps, first check $jobbag->{'file_issues'}{group}{status}
	# if there's a file level reject, all transactions will inherit this.
	# as of WR-483, the only file level reject issues are zero transactions in the file group header
	# or the group control sum does not match the accumulated check sums

	if ( defined $jobbag->{'file_issues'}{group}{status} and 'RJCT' eq $jobbag->{'file_issues'}{group}{status} ) {
		$status          = $jobbag->{'file_issues'}{group}{status};
		$reason_code     = $jobbag->{'file_issues'}{group}{reason_code};
		$business_reason = $jobbag->{'file_issues'}{group}{business_reason};

		push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
			{
			payment_id      => $set->{check_details}{pmt_id},
			status          => $status,
			reason_code     => $reason_code,
			check_amount    => $set->{check_details}{check_amount},
			currency        => $set->{check_details}{check_currency},
			transaction_id  => $set->{payer_details}{transaction_id},
			business_reason => $business_reason,
			check_number    => $set->{check_details}{check_number},
			account_number  => $set->{check_details}{account_number},
			routing_number  => $set->{check_details}{check_number},
			ccs_endtoend_id => $set->{check_details}{ccs_endtoend_id},
			check_date      => $set->{check_details}{check_date},
			};

		# increment overall count
		$jobbag->{reject}++;
		$jobbag->{reject_chk_amount} =
			sprintf( "%.2f", $jobbag->{reject_chk_amount} + $set->{check_details}{check_amount} );

		#increment transaction-level count and accumulated check amounts
		$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
		$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
			( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) + $set->{check_details}{check_amount} );

		$jobbag->{reject_type}{file}++;

		return (
			$jobbag->{'file_issues'}{group}{status},
			$jobbag->{'file_issues'}{group}{reason_code},
			$jobbag->{'file_issues'}{group}{business_reason}
		);

	}
	# if there's a Payment Information group level reject, all transactions with the PmtInfID will inherit this.
	elsif ( defined $jobbag->{pmt_inf}{group}{status} && 'RJCT' eq $jobbag->{pmt_inf}{group}{status} ) {

		if (   $set->{payer_details}{transaction_id} eq $jobbag->{pmt_inf}{group}{transaction_id}
			&& $set->{check_details}{pmt_id} eq $jobbag->{pmt_inf}{group}{payment_id} )
		{
			# transaction already rejected
			$jobbag->{reject_type}{transaction}++;

			return (
				$jobbag->{pmt_inf}{group}{status},
				$jobbag->{pmt_inf}{group}{reason_code},
				$jobbag->{pmt_inf}{group}{business_reason}
			);

		}
		elsif ($set->{payer_details}{transaction_id} eq $jobbag->{pmt_inf}{group}{transaction_id}
			&& $set->{check_details}{pmt_id} ne $jobbag->{pmt_inf}{group}{payment_id} )
		{
			$status          = $jobbag->{pmt_inf}{group}{status};
			$reason_code     = $jobbag->{pmt_inf}{group}{reason_code};
			$business_reason = $jobbag->{pmt_inf}{group}{business_reason};

			push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
				{
				payment_id      => $set->{check_details}{pmt_id},
				status          => $status,
				reason_code     => $reason_code,
				check_amount    => $set->{check_details}{check_amount},
				currency        => $set->{check_details}{check_currency},
				transaction_id  => $set->{payer_details}{transaction_id},
				business_reason => $business_reason,
				check_number    => $set->{check_details}{check_number},
				account_number  => $set->{check_details}{account_number},
				routing_number  => $set->{check_details}{check_number},
				ccs_endtoend_id => $set->{check_details}{ccs_endtoend_id},
				check_date      => $set->{check_details}{check_date},
				};

			# increment overall count
			$jobbag->{reject}++;
			$jobbag->{reject_chk_amount} =
				sprintf( "%.2f", $jobbag->{reject_chk_amount} + $set->{check_details}{check_amount} );

			#increment transaction-level count and accumulated check amounts
			$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
			$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
				( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) +
					$set->{check_details}{check_amount} );

			$jobbag->{reject_type}{transaction}++;

			return (
				$jobbag->{pmt_inf}{group}{status},
				$jobbag->{pmt_inf}{group}{reason_code},
				$jobbag->{pmt_inf}{group}{business_reason}
			);
		}
	}
	elsif ( defined $jobbag->{pmt_inf}{group}{status} && 'ACCP' eq $jobbag->{pmt_inf}{group}{status} ) {

		if ( defined $jobbag->{'proc_transactions'}{transaction}{reject} ) {
			foreach my $rejected_trans ( @{ $jobbag->{proc_transactions}{transaction}{reject} } ) {

				( my $temp_ccs_id = $set->{check_details}{ccs_endtoend_id} ) =~ s/^\s+|\s+$//g;

				if ( $rejected_trans->{ccs_endtoend_id} eq $temp_ccs_id ) {
					return (
						$rejected_trans->{status},
						$rejected_trans->{reason_code},
						$rejected_trans->{business_reason}
					);
				}
				else {
					next;
				}
			}
		}

		$status          = '';
		$reason_code     = '';
		$business_reason = '';
		my $found_issue = 0;

		my ( $file_val, $payee_val, $check_val, $dupe_val ) = ( undef, undef, undef, undef );

		( $file_val, $found_issue, $reason_code, $business_reason ) =
			$this->validate_payer_details( $set, $jobbag, $found_issue );    #PmtInf level

		if ( !$found_issue ) {
			( $payee_val, $found_issue, $reason_code, $business_reason ) =
				$this->validate_payee_details( $set, $jobbag, $found_issue );    # transaction level
		}

		if ( !$found_issue ) {    # we only want one transaction issue reported per set
			( $check_val, $found_issue, $reason_code, $business_reason ) =
				$this->validate_check_details( $set, $jobbag );    # transaction level
		}

		if ( !$found_issue ) {                                     # we only want one transaction issue reported per set
			$dupe_val = $this->check_for_dupes( $set, $jobbag );    # transaction level
		}

		if (   $file_val eq 'ACCP'
			&& $payee_val eq 'ACCP'
			&& $check_val eq 'ACCP'
			&& $dupe_val eq 'ACCP'
			&& $reason_code eq '0'
			&& $business_reason eq '0' )
		{

			# if there is a file level RJCT from either the ConverterPreProcesser or
			# PmtInf RJCT from ConverterBusinessRules or Converter
			# $status must be set to RJCT; otherwise keep the ACCP
			if ( defined $jobbag->{'file_issues'}{group}{status} and 'RJCT' eq $jobbag->{'file_issues'}{group}{status} )
			{
				$status = 'RJCT';
			}
			elsif ( defined $jobbag->{pmt_inf}{group}{status} and 'RJCT' eq $jobbag->{pmt_inf}{group}{status} ) {
				$status = 'RJCT';
			}
			else {
				$status = 'ACCP';
			}

			push @{ $jobbag->{'proc_transactions'}{transaction}{accept} },
				{
				payment_id      => $set->{check_details}{pmt_id},
				status          => $status,
				reason_code     => $reason_code,
				check_amount    => $set->{check_details}{check_amount},
				currency        => $set->{check_details}{check_currency},
				transaction_id  => $set->{payer_details}{transaction_id},
				business_reason => $business_reason,
				check_number    => $set->{check_details}{check_number},
				account_number  => $set->{check_details}{account_number},
				routing_number  => $set->{check_details}{check_number},
				ccs_endtoend_id => $set->{check_details}{ccs_endtoend_id},
				check_date      => $set->{check_details}{check_date},
				};

			# increment overall ACCP count
			$jobbag->{accept}++;
			$jobbag->{accept_chk_amount} =
				sprintf( "%.2f", $jobbag->{accept_chk_amount} + $set->{check_details}{check_amount} );

			#increment transaction-level count and accumulated check amounts
			$jobbag->{'proc_transactions'}{transaction}{accept_count}++;
			$jobbag->{'proc_transactions'}{transaction}{accept_sum} = sprintf( "%.2f",
				( $jobbag->{'proc_transactions'}{transaction}{accept_sum} || 0 ) +
					$set->{check_details}{check_amount} );

			return ( $status, $reason_code, $business_reason );
		}
	}

	return ( $status, $reason_code, $business_reason );    # all transaction levels checks passed
}

sub validate_payer_details {
	my ( $this, $set, $jobbag, $found_issue ) = @_;
	my $status          = '';
	my $reason_code     = '';
	my $business_reason = '';

	if ( defined $jobbag->{pmt_inf}{group}{status} && 'RJCT' eq $jobbag->{pmt_inf}{group}{status} ) {
		$status      = 'RJCT';
		$found_issue = 1;
		return (
			$jobbag->{pmt_inf}{group}{status},
			$found_issue,
			$jobbag->{pmt_inf}{group}{reason_code},
			$jobbag->{pmt_inf}{group}{business_reason}
		);
	}

	if ( !defined $jobbag->{payer_details}{name} || $jobbag->{payer_details}{name} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payer Name is missing';
		$found_issue     = 1;
	}
	if ( !defined $jobbag->{payer_details}{street_name} || $jobbag->{payer_details}{street_name} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payer Street Name is missing';
		$found_issue     = 1;
	}
	if ( !defined $jobbag->{payer_details}{city} || $jobbag->{payer_details}{city} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payer City is missing';
		$found_issue     = 1;
	}
	if ( !defined $jobbag->{payer_details}{state} || $jobbag->{payer_details}{state} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payer State is missing';
		$found_issue     = 1;
	}
	if ( !defined $jobbag->{payer_details}{zip_code} || $jobbag->{payer_details}{zip_code} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payer Zip is missing';
		$found_issue     = 1;
	}

	if ( 'RJCT' eq $status && 1 == $found_issue ) {
		$jobbag->{pmt_inf}{group}{status}          = $status;
		$jobbag->{pmt_inf}{group}{reason_code}     = $reason_code;
		$jobbag->{pmt_inf}{group}{business_reason} = $business_reason;
		$jobbag->{pmt_inf}{group}{date_time}       = $jobbag->{convert_timestamp};
		$jobbag->{pmt_inf}{group}{transaction_id}  = $jobbag->{payer_details}{transaction_id};
		$jobbag->{pmt_inf}{group}{payment_id}      = $set->{check_details}{pmt_id};

		push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
			{
			payment_id      => $set->{check_details}{pmt_id},
			status          => $status,
			reason_code     => $reason_code,
			check_amount    => $set->{check_details}{check_amount},
			currency        => $set->{check_details}{check_currency},
			transaction_id  => $set->{payer_details}{transaction_id},
			business_reason => $business_reason,
			check_number    => $set->{check_details}{check_number},
			account_number  => $set->{check_details}{account_number},
			routing_number  => $set->{check_details}{check_number},
			ccs_endtoend_id => $set->{check_details}{ccs_endtoend_id},
			check_date      => $set->{check_details}{check_date},
			};

		# increment overall count
		$jobbag->{reject}++;
		$jobbag->{reject_chk_amount} =
			sprintf( "%.2f", $jobbag->{reject_chk_amount} + $set->{check_details}{check_amount} );

		#increment transaction-level count and accumulated check amounts
		$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
		$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
			( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) + $set->{check_details}{check_amount} );

		$jobbag->{reject_type}{transaction}++;

		return ( $status, $found_issue, $reason_code, $business_reason );
	}

	#collect list of transaction_id
	foreach my $existing_id ( @{ $jobbag->{file_ids} } ) {
		if ( $jobbag->{payer_details}{transaction_id} eq $existing_id ) {
			last;
		}
		else {
			push @{ $jobbag->{file_ids} }, $jobbag->{payer_details}{transaction_id};
		}
	}

	return ( 'ACCP', 0, 0, 0 );
}

sub validate_payee_details {
	my ( $this, $set, $jobbag, $found_issue ) = @_;

	my $status          = '';
	my $reason_code     = '';
	my $business_reason = '';

	if ( !defined $set->{check_details}{name} || $set->{check_details}{name} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payee Name is missing';
		$found_issue     = 1;

	}
	if ( !defined $set->{check_details}{street_name} || $set->{check_details}{street_name} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payee Street Name OR Address Line is missing';
		$found_issue     = 1;
	}
	if ( !defined $set->{check_details}{city} || $set->{check_details}{city} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payee City is missing';
		$found_issue     = 1;
	}
	if ( !defined $set->{check_details}{state} || $set->{check_details}{state} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payee State is missing';
		$found_issue     = 1;

	}
	if ( !defined $set->{check_details}{zip_code} || $set->{check_details}{zip_code} eq '' ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Payee Zip is missing';
		$found_issue     = 1;
	}
	if ( 'RJCT' eq $status && 1 == $found_issue ) {
		push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
			{
			payment_id      => $set->{check_details}{pmt_id},
			status          => $status,
			reason_code     => $reason_code,
			check_amount    => $set->{check_details}{check_amount},
			currency        => $set->{check_details}{check_currency},
			transaction_id  => $set->{payer_details}{transaction_id},
			business_reason => $business_reason,
			check_number    => $set->{check_details}{check_number},
			account_number  => $set->{check_details}{account_number},
			routing_number  => $set->{check_details}{check_number},
			ccs_endtoend_id => $set->{check_details}{ccs_endtoend_id},
			check_date      => $set->{check_details}{check_date},
			};

		# increment overall count
		$jobbag->{reject}++;
		$jobbag->{reject_chk_amount} =
			sprintf( "%.2f", $jobbag->{reject_chk_amount} + $set->{check_details}{check_amount} );

		#increment transaction-level count and accumulated check amounts
		$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
		$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
			( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) + $set->{check_details}{check_amount} );

		$jobbag->{reject_type}{transaction}++;

		return ( $status, $found_issue, $reason_code, $business_reason );
	}

	return ( 'ACCP', 0, 0, 0 );
}

sub validate_check_details {
	my ( $this, $set, $jobbag, $found_issue ) = @_;

	my $status          = '';
	my $reason_code     = '';
	my $business_reason = '';

	if (   defined $jobbag->{pmt_inf}{group}{reason_code}
		&& 'CH21' eq $jobbag->{pmt_inf}{group}{reason_code}
		&& 'Account Number is Missing' eq $jobbag->{pmt_inf}{group}{business_reason} )
	{
		$status      = 'RJCT';
		$found_issue = 1;
		return ( $status, $found_issue );
	}

	if ( $set->{check_details}{check_number} =~ /^\s*$/ && $set->{check_details}{check_number} !~ /\d+$/ ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Check Number is missing';
		$found_issue     = 1;
	}

	if ( $set->{check_details}{check_number} =~ /\D/ ) {
		( my $temp_chk_number = $set->{check_details}{check_number} ) =~ s/^\s+|\s+$//g;

		if ( $temp_chk_number =~ /\D/ ) {
			$status          = 'RJCT';
			$reason_code     = 'FF09';
			$business_reason = 'Cheque Number is not numeric';
			$found_issue     = 1;
		}
	}

	if ( '' eq $set->{check_details}{check_date} ) {
		$status          = 'RJCT';
		$reason_code     = 'CH21';
		$business_reason = 'Check Date is missing';
		$found_issue     = 1;
	}

	if ( defined $set->{check_details}{check_number} && length( $set->{check_details}{check_number} ) > 10 ) {
		$status          = 'RJCT';
		$reason_code     = 'NARR';
		$business_reason = 'Cheque Number exceeds 10 digits';
		$found_issue     = 1;
	}

	if ( $jobbag->{memo}{length} ) {
		$status          = 'RJCT';
		$reason_code     = 'NARR';
		$business_reason = 'Memo Field – Max character limited exceeded';
		$found_issue     = 1;

	}

	if ( defined $set->{check_details}{check_amount} ) {

		if ( $set->{check_details}{check_amount} <= 0.00 ) {

			if ( 1 == $jobbag->{'file_issues'}{undefined}{check_amount} ) {
				$status          = 'RJCT';
				$reason_code     = 'CH21';
				$business_reason = 'Check Amount is missing';
				$found_issue     = 1;

			}
			else {
				$status          = 'RJCT';
				$reason_code     = 'AM12';
				$business_reason = 'Cheque Amount is 0 or negative value';
				$found_issue     = 1;
			}

		}
		elsif ( $set->{check_details}{check_amount} =~ /\(\d*\.\d\d\)/ ) {
			$status          = 'RJCT';
			$reason_code     = 'AM12';
			$business_reason = 'Cheque Amount  is 0 or negative value';
			$found_issue     = 1;
		}

	}

	if ( ( defined $set->{check_details}{check_currency} )
		&& $set->{check_details}{check_currency} ne "USD" )
	{
		$status          = 'RJCT';
		$reason_code     = 'CURR';
		$business_reason = 'Currency not in USD';
		$found_issue     = 1;

	}
	if ( 'RJCT' eq $status && 1 == $found_issue ) {
		push @{ $jobbag->{'proc_transactions'}{transaction}{reject} },
			{
			payment_id      => $set->{check_details}{pmt_id},
			status          => $status,
			reason_code     => $reason_code,
			check_amount    => $set->{check_details}{check_amount},
			currency        => $set->{check_details}{check_currency},
			transaction_id  => $set->{payer_details}{transaction_id},
			business_reason => $business_reason,
			check_number    => $set->{check_details}{check_number},
			account_number  => $set->{check_details}{account_number},
			routing_number  => $set->{check_details}{check_number},
			ccs_endtoend_id => $set->{check_details}{ccs_endtoend_id},
			check_date      => $set->{check_details}{check_date},
			};

		# increment overall count
		$jobbag->{reject}++;
		$jobbag->{reject_chk_amount} =
			sprintf( "%.2f", $jobbag->{reject_chk_amount} + $set->{check_details}{check_amount} );

		#increment transaction-level count and accumulated check amounts
		$jobbag->{'proc_transactions'}{transaction}{reject_count}++;
		$jobbag->{'proc_transactions'}{transaction}{reject_sum} = sprintf( "%.2f",
			( $jobbag->{'proc_transactions'}{transaction}{reject_sum} || 0 ) + $set->{check_details}{check_amount} );

		$jobbag->{reject_type}{transaction}++;

		## skipping the rest of the checks and getting next record
		$found_issue = 1;

		return ( $status, $found_issue, $reason_code, $business_reason );
	}

	return ( 'ACCP', 0, 0, 0 );
}

sub check_for_dupes() {
	my ( $this, $set, $jobbag ) = @_;

	my $status          = '';
	my $reason_code     = '';
	my $business_reason = '';
	my %transaction_obj;

	# iterate over proc transaction reject off of ccs_endtoend_id
	if ( defined $jobbag->{'Duplicate_checks'}
		and $jobbag->{'Duplicate_checks'}{ $set->{check_details}{ccs_endtoend_id} } )
	{
		print "\n*** !!! Set has duplicate CCS transaction ID: $set->{check_details}{ccs_endtoend_id}\n";
		$status = 'RJCT';
		return $status;
	}

	# remove leading spaces for database query
	( my $temp_chk_number  = $set->{check_details}{check_number} ) =~ s/^\s+|\s+$//g;
	( my $temp_acct_number = $set->{check_details}{account_number} ) =~ s/^\s+|\s+$//g;
	( my $temp_rout_number = $set->{check_details}{routing_number} ) =~ s/^\s+|\s+$//g;

	#my $enc_routing_number = DupCheck_Utils::transform_routing_number( $temp_rout_number, $temp_acct_number );

	# recheck duplicate check database in case the routing number 121100782 was in the pain001
	# and replaced by a different routing_number by querying EnCompass2
	$transaction_obj{payment_id}      = $set->{check_details}{pmt_id};
	$transaction_obj{status}          = $status;
	$transaction_obj{reason_code}     = $reason_code;
	$transaction_obj{check_amount}    = $set->{check_details}{check_amount};
	$transaction_obj{currency}        = $set->{check_details}{check_currency};
	$transaction_obj{transaction_id}  = $set->{payer_details}{transaction_id};
	$transaction_obj{business_reason} = $business_reason;
	$transaction_obj{check_no}        = $temp_chk_number;
	$transaction_obj{payee}           = $set->{check_details}{name};
	$transaction_obj{file_name}       = $jobbag->{'orig_xml_file'};
	$transaction_obj{transit_number}  = $temp_rout_number;
	$transaction_obj{acct_no}         = $temp_acct_number;
	$transaction_obj{ccs_endtoend_id} = $set->{check_details}{ccs_endtoend_id};
	$transaction_obj{check_date}      = $set->{check_details}{check_date};
	$transaction_obj{package}         = 'Converter';

	my ( $enc_routing_number, $enc_account_number );
	( $status, $enc_routing_number, $enc_account_number ) = DupCheck_Utils::account_lookup( $jobbag, %transaction_obj );

	return $status;
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

sub _check_register_hash {
	my ( $this, $filename, $jobbag, $set ) = @_;

	my $formatted_acctno = $set->{check_details}{account_number};
	$formatted_acctno =~ s/\s//g;
	$formatted_acctno =~ s/^\d{4}/XXXX/;

	$jobbag->{ $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} }{number_of_checks}++;
	$jobbag->{ $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} }{check_total} =
		sprintf( "%.2f",
		( $jobbag->{ $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} }{check_total} || 0 ) +
			$set->{check_details}{check_amount} );

	my $check_number = $set->{check_details}{check_number};
	$check_number =~ s/^\s+|\s+$//g;

	push @{ $jobbag->{check_register_report_details}
			{ $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{checkreg_file} } },
		{
		'check_number'      => $check_number,
		'check_date'        => $set->{check_details}{check_date},
		'payee_line_1'      => $set->{addressee_details}{name},
		'check_amount'      => $set->{check_details}{check_amount},
		'formatted_acctno'  => $formatted_acctno,
		'acct_number_total' => $jobbag->{check_details}{number_of_checks},
		'acct_number_sum'   => $jobbag->{check_details}{control_sum},
		};

	++$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{accp}{count};
	$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{accp}{value} = sprintf( "%.2f",
		( $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{accp}{value} || 0 ) +
			$set->{check_details}{check_amount} );

	push @{ $jobbag->{$filename}{acctno} }, $formatted_acctno;

	return 1;
}

sub _rjct_register_hash {
	my ( $this, $filename, $jobbag, $set, $business_reason, $acctno ) = @_;

	my $formatted_acctno = $set->{check_details}{account_number};
	$formatted_acctno =~ s/\s//g;
	$formatted_acctno =~ s/^\d{4}/XXXX/;

	$jobbag->{ $jobbag->{$filename}{exception_file} }{number_of_checks}++;
	$jobbag->{ $jobbag->{$filename}{exception_file} }{check_total} = sprintf( "%.2f",
		( $jobbag->{ $jobbag->{$filename}{exception_file} }{check_total} || 0 ) + $set->{check_details}{check_amount} );

	my $check_number = $set->{check_details}{check_number};
	$check_number =~ s/(?:^\s+|\s+$)//g;

	push @{ $jobbag->{ $jobbag->{$filename}{exception_file} }{details} },
		{
		'check_number'    => $check_number,
		'acct_number'     => $acctno,
		'business_reason' => $business_reason,
		};

	++$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rejected}{count};
	$jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rejected}{value} = sprintf( "%.2f",
		( $jobbag->{$filename}{formatted_acctno}{$formatted_acctno}{rejected}{value} || 0 ) +
			$set->{check_details}{check_amount} );

	push @{ $jobbag->{$filename}{acctno} }, $formatted_acctno;

	return 1;
}

1;

__END__
