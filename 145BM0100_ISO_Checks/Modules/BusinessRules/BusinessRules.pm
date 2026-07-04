package BusinessRules;

use 5.010;

use strict;
use warnings;

use base qw(GenericBusinessRule);

################################################################################

use Data::Dumper;
$Data::Dumper::Indent   = 1;
$Data::Dumper::Sortkeys = 1;

################################################################################

#------------------------------------------------------
# Subroutine: Init Rule
#	This subroutine executes once.
#	Any business rule initialisation logic can be performed here.
#------------------------------------------------------
sub init_rule {
	my ( $this, $jobbag ) = @_;

	return 1;
}

#------------------------------------------------------
# Subroutine: Execute Rule
#	Get the raw set as created by the data reader.
#	The raw set is transformed into a rule set that
#	the program sees.
#------------------------------------------------------
sub execute_rule {
	my ( $this, $raw_set, $jobbag, $rule_set ) = @_;

	return 1;
}

#------------------------------------------------------
# Subroutine: CleanUp Rule
#	Actions taken when an exception occurs
#	These actions are performed before the next set of data is retrieved.
#	Errors could be logged.
#------------------------------------------------------
sub cleanup_rule {
	my ( $this, $raw_set, $jobbag, $rule_set ) = @_;

	return 1;
}

#------------------------------------------------------
# Subroutine: Finalise Rule
#	This subroutine executes once at the end of processing.
#------------------------------------------------------
sub finalise_rule {
	my ( $this, $jobbag ) = @_;

	return 1;
}

1;
