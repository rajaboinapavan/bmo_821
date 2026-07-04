package SampleSetup;

use 5.010;

use strict;
use warnings;

use base qw(GenericProcessor);

################################################################################

# JEF-----------------------------------------------------------------

sub run {
	my ( $this, $jobbag ) = @_;

	$this->SUPER::run($jobbag);
	$jobbag->{__run_params}{run_num} ||= 999999999;

	return;
}

# JEF-----------------------------------------------------------------

1;
