package Base::ProcessorBase;
#this is just here to workaround JEF's less than adequate implementation
# allows the passing of args from run.pl to the 'run' method
# ...although now you overrride 'process' instead

use base qw(GenericProcessor);

use strict;
use Data::Dumper;


# JEF-----------------------------------------------------------------

sub new {
	my ($object, $globals, @args) = @_;

	my $class = ref($object) || $object;
	my $this = $class->SUPER::new($globals, @args);
	$this->{args} = \@args;
	bless($this, $class);
	return $this;
}

sub run {
	my $this = shift @_;
	$this->process(@_, @{$this->{args}});
}

# JEF-----------------------------------------------------------------

1;