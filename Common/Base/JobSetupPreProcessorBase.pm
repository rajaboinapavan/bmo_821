package Base::JobSetupPreProcessorBase;

use base qw(Base::ProcessorBase);

use strict;
use Data::Dumper;

use AutoStreamSetup;

sub new {
	my ($object, $globals, @args) = @_;

	my $class = ref($object) || $object;
	my $this = $class->SUPER::new($globals, @args);
	$this->{args} = \@args;
	bless($this, $class);
	return $this;
}

sub process {
	my ($this, $jobbag, $config) = @_;

	my $ass;
	$config = [$jobbag->{__config}{job}{job_code}, undef, $jobbag->{__config}{job}{site}] if not defined $config;

	$ass = new AutoStreamSetup($config);

	my $setups = $ass->get_setups();
	my $stream_details = $ass->get_stream_details();	

	$this->update_setups($jobbag, $setups, $stream_details);

	$ass->build_setup();

	$this->update_calls($jobbag, $ass->get_calls());

	$ass->init_job();

	#$ass->create_report();
	#$ass->create_stock_matrix();

	$jobbag->{__ass} = $ass;
	$jobbag->{__job} = $ass->get_job_details();
	$jobbag->{__streams} = $ass->get_stream_details();

}

sub update_setups {
	my ($this, $jobbag, $setup) = @_;

}

sub update_calls {
	my ($this, $jobbag, $setup) = @_;

}


1;

=pod
	This preprocessor performs routine job setup via the AutoStreamSetup module.
=cut