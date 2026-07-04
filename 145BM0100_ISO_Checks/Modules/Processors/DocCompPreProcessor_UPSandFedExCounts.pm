package DocCompPreProcessor_UPSandFedExCounts;

use base qw(JobEngine_PreProcessor);

use strict;
use warnings;
use Data::Dumper;
use CDS_Utils;

################################################################################

# JEF-----------------------------------------------------------------

sub run {
	my ( $this, $jobbag ) = @_;

# read the po xml to pre-determine the number of sets in each group. This information is added to the bulk ship batch cover page
	foreach my $filename ( @{ $jobbag->{__run_params}{data_files} } ) {

		if ( $filename =~ /po\.xml$/i ) {

			my $data_fh = DataFile::JobEngineXML->open(
				filename   => "$jobbag->{__run_params}{data_dir}\\$filename",
				sets_xpath => $jobbag->{__config}{data_reader}{set_xpath},
				id_path    => $jobbag->{__config}{data_reader}{set_id_xpath},
			);

			while ( my $set = $data_fh->next() ) {

				if (    $set->get( xpath => 'Payer/Special_Handling_Code' )
					and $set->get('File_Information/Courier_Information/Courier_Option') )
				{
					$jobbag->{courier}{ $set->get('File_Information/Courier_Information/Courier_Option') }
						{ $set->get( xpath => 'Payer/Special_Handling_Code' ) }{count} += 1;
				}
				else {
					next;
				}
			}
			$data_fh->close;
		}
	}

	$this->SUPER::run($jobbag);

	return;
}

# JEF-----------------------------------------------------------------

1;
