package ContentSegments::Check;

use 5.010;

use strict;
use warnings;

sub get_module_signature {
	return '87bef2e7cb25155ffdb88ae531e6f58a';
}    # automatically added by dependency script - please do not touch

use BaseSegments::Check;
use base qw(BaseSegments::Check);

sub render {
	my ( $this, %args ) = @_;

	return $this->SUPER::render(%args);

}

sub get_segment_info {
	my ($this) = @_;

	return {
		name        => 'Check',
		description => 'Check Segment',
	};
}

1;
