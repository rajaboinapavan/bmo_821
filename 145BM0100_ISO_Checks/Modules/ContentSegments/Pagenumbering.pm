package ContentSegments::Pagenumbering;

use 5.010;

use strict;
use warnings;

sub get_module_signature {
	return 'bc4de180e074c9409e475e05f9e37d21';
}    # automatically added by dependency script - please do not touch

use BaseSegments::Pagenumbering;
use base qw(BaseSegments::Pagenumbering);

use Data::Dumper;

sub render {
	my ( $this, %args ) = @_;

	return $this->SUPER::render(%args);
}

sub get_segment_info {
	my ($this) = @_;
	return {
		name        => 'Pagenumbering',
		description => 'Pagenumbering Segment',
	};
}

1;
