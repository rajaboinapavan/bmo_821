package DocCompPreProcessor;

use 5.010;

use strict;
use warnings;

use base qw(JobEngine_PreProcessor);

use Getopt::Long qw(:config pass_through);

################################################################################

# JEF-----------------------------------------------------------------

sub run {
	my ( $this, $jobbag ) = @_;

	GetOptions(
		'threshhold=s'      => \$jobbag->{extra_options}{threshhold},
		'sleep=s'           => \$jobbag->{extra_options}{sleep},
		'alert_every=s'     => \$jobbag->{extra_options}{alert_every},
		'pdf_samples=s'     => \$jobbag->{extra_options}{pdf_samples},
		'input_folder=s'    => \$jobbag->{extra_options}{input_folder},
		'fulfillment_dir=s' => \$jobbag->{extra_options}{fulfillment_dir},
	);

	return $this->SUPER::run($jobbag);
}

# JEF-----------------------------------------------------------------

1;
