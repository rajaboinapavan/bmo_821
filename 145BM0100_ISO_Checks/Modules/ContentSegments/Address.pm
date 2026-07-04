package ContentSegments::Address;

use 5.010;

use strict;
use warnings;

sub get_module_signature {
	return 'dec209620f44bb524afae889d34125b3';
}    # automatically added by dependency script - please do not touch

use BaseSegments::Address;
use base qw(BaseSegments::Address);

use Data::Dumper;

sub render {
	my ( $this, %args ) = @_;

	return $this->SUPER::render(%args);
}

sub get_segment_info {
	my ($this) = @_;
	return {
		name        => 'Address',
		description => 'Address Segment',
	};
}

1;
