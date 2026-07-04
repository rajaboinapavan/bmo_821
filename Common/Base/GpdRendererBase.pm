package Base::GpdRendererBase;

use base qw(GenericRendering);
use Data::Dumper;

use GPD;

use Kaboom;
use CdsCommon;
use AdmXml;

use Utils::JEF_Exception;
#use Sort::AustPost;

use AutoStreamSetup;

sub init_render {
	my ($this, $jobbag) = @_;
	$this->SUPER::init_render($jobbag);
	$this->{jobbag} = $jobbag;
	$this->{allow_unemitted_set} = 0;

	my $streams = $jobbag->{__streams};
	$this->{streams} = $streams;
	for my $stream_key (keys %$streams) {
		$this->select_gpd($stream_key);
		my $stream = $streams->{$stream_key};
		my $workflow = $stream->{workflow};
		$this->init_stream($jobbag, $stream_key, $stream->{stream}{prod_number}, $stream->{workflow});
	}
}

sub render {
	my ($this, $set, $jobbag) = @_;
	$this->SUPER::render($set, $jobbag);

	die "Safety check - previous set not emitted. Set \$this->{allow_unemitted_set} to true in the renderer to ignore" if not $this->{allow_unemitted_set} and get_cur_num_sheets_in_set();
	add_set_tags id => exists $set->{__id} ? $set->{__id} : $jobbag->{__data}{accumulated_set_no};
}

sub finalise_render {
	my ($this, $jobbag) = @_;
	$jobbag->{__ass}->finalise_job();
}

sub select_gpd {
	my ($this, $key) = @_;
	die "Undefined stream key" if not defined $key;
	die "Stream does not exist: $key" if not exists $this->{streams}{$key};
	use_gpd($this->{streams}{$key}{gpd});
}

sub emit_gpd_set {
	my ($this, $key) = @_;
	$this->select_gpd($key) if @_ == 2;
	emit_set;
}

sub streams {
	my ($this) = @_;
	return values %{$this->{streams}};
}

sub stream_keys {
	my ($this) = @_;
	return keys %{$this->{streams}};
}

sub get_stream {
	my ($this, $key) = @_;
	die "Undefined stream key" if not defined $key;
	die "Stream does not exist: $key" if not exists $this->{streams}{$key};
	return $this->{streams}{$key};
}

###########################################################################


1;