package ContentSegments::Check_Logo;

use 5.010;

use strict;
use warnings;

sub get_module_signature {
	return 'bb04bb170323c9ef98be11f54559fec8';
}    # automatically added by dependency script - please do not touch

use BaseSegments::Check_Logo;
use base qw(BaseSegments::Check_Logo);

sub render {
	my ( $this, %args ) = @_;

	return $this->SUPER::render(%args);

}

sub get_segment_info {
	my ($this) = @_;

	return {
		name        => 'Check_Logo',
		description => 'Check Logo',
	};
}

1;
