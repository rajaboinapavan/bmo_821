package GetGraphicsLibsPreProcessor;

use 5.010;

use strict;
use warnings;

use base qw(JobEngine_PreProcessor);

use Data::Dumper;

use GPD;

################################################################################

# JEF-----------------------------------------------------------------

sub run {
	my ( $this, $jobbag ) = @_;

	my $bank_details = CcsCommon::ini2h( $ENV{CCS_SETTINGS} . '/BankDetails.ini' );

	my @cum_signature_path;
	my $signature_folder;
	my $po_graphics_path = CcsCommon::get_setting( 'graphics', 'po_path' );

	foreach my $filename ( @{ $jobbag->{__run_params}{data_files} } ) {
		next if $filename =~ /trigger/i;

		my $data_fh = DataFile::JobEngineXML->open(
			filename   => "$jobbag->{__run_params}{data_dir}\\$filename",
			sets_xpath => $jobbag->{__config}{data_reader}{set_xpath},
			id_path    => $jobbag->{__config}{data_reader}{set_id_xpath},
		);

		while ( my $set = $data_fh->next() ) {

			my $RoutingNo = $set->get('Check_Data/Routing_Number');
			if ( $bank_details->{$RoutingNo} ) {
				$bank_details->{$RoutingNo}{sig_folder} = $bank_details->{default}{sig_folder}
					if !exists( $bank_details->{$RoutingNo}{sig_folder} );
			}
			else {
				Utils::JEF_Exception::terminate("\nRouting number: $RoutingNo is not in the list of supported bank.");
			}

			#signature file subfolder to be used for set_graphic_lib
			my $poxml_sigpath;
			if ( $set->get( xpath => 'Check_Data/Signature_Location', must_exist => 0 ) ) {
				$poxml_sigpath =
					( split( /\\/, $set->get( xpath => 'Check_Data/Signature_Location', must_exist => 0 ) ) )[-1];
			}
			else {
				$poxml_sigpath = $bank_details->{$RoutingNo}{sig_folder};
			}

			if ( !$signature_folder ) {
				$signature_folder = $poxml_sigpath;
				push( @cum_signature_path, CcsCommon::get_setting( 'graphics', 'po_path' ) . "\\$poxml_sigpath" );
			}
			else {
				if ( $signature_folder !~ /$poxml_sigpath/i ) {
					$signature_folder .= '|' . $poxml_sigpath;
					push( @cum_signature_path, CcsCommon::get_setting( 'graphics', 'po_path' ) . "\\$poxml_sigpath" );
				}
			}

		}

		# Close the data file handler
		$data_fh->close();

	}

	set_graphic_libs(@cum_signature_path);

	$this->SUPER::run($jobbag);

	return;
}

# JEF-----------------------------------------------------------------

1;
