package ContentSegments::Logo;

use 5.010;

use strict;
use warnings;

sub get_module_signature {
	return '17cd4dddca3294e1fcc1f7da3852f6b2';
}    # automatically added by dependency script - please do not touch

use BaseSegments::Logo;
use base qw(BaseSegments::Logo);

sub render {
	my ( $this, %args ) = @_;

	return $this->SUPER::render(%args);

}

sub get_segment_info {
	my ($this) = @_;

	return {
		name        => 'Logo',
		description => 'Client Logo',
	};
}

1;
