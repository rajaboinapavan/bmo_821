package Reports::MailSummary;

=head1 NAME

NA::PostProcess::MailSummary - Creates a MailSummary report


=head1 DESCRIPTION

This runs as a JEF post-processor. It collects all GPD streams that were created and creates a report
specifying the stream name, the set count, and whether this stream is to be mailed or not.

(Streams that aren't mailed include things like sets created for DSS insertion.)

=head1 BUGS/QUIRKS


=head1 COPYRIGHT

Copyright 2010 (C), Computershare Document Services. All Rights Reserved

=cut

use base qw(GenericProcessor);
use strict;
use Data::Dumper;

use AdmXml;
use CcsCommon;

use NA::Std::Utils;

# these are the rows for the report and how to format them.
my @reportstyle = (
	{ name=>'rowname',title=>'Print Run',type=>'s',size=>'-35' },
	{ name=>'mailed',title=>'To Mail',type=>'d',size=>'10' },
	{ name=>'notmailed',title=>'Not To Mail',type=>'d',size=>'13' }
);


# ######################
# create the report.
sub run {
	my ($this, $jobbag) = @_;
	my $logFile = NA::Std::Utils::getLogFileName($jobbag,'MailSummaryReport');

	open(LOGFILE, ">$logFile") or Utils::JEF_Exception::terminate("Unable to open $logFile for writing: $!");

	# file header
	printf(LOGFILE "%s", "MAIL SUMMARY REPORT\n");
	printf(LOGFILE "%s", $jobbag->{__config}{job}{job_name} . "\n");
	printf(LOGFILE "%s %s\n", CcsCommon::get_date_time_strings());
	printf(LOGFILE "CCS RUN NUMBER: %04d\n\n",$jobbag->{__run_params}{run_num});
	printf(LOGFILE join("",map({"%$_->{size}s"} @reportstyle),"\n\n"),map({$_->{title}} @reportstyle));

	# file table data
	my %summarydata=(rowname=>'Total','mailed'=>0,'notmailed'=>0);

	foreach my $streams (sort(keys %{$jobbag->{__streams}})) {
		my $stream = $jobbag->{__ass}{data}{gpds}{$streams}{adm}{stream}{name};
		my $file = "$stream.adm.xml";

		if(-e $file) {
			my(%setdata)=(rowname=>$stream,'mailed'=>0,'notmailed'=>0);
			my ($adm,$extra) = AdmXml::xml_to_struct($file);
			if($adm->{workflow}{lodge}) {
				$setdata{mailed}=$adm->{stream}{'total_sets'};
			}
			else {
				$setdata{notmailed}=$adm->{stream}{'total_sets'};
			}
			$summarydata{mailed}+=$setdata{mailed};
			$summarydata{notmailed}+=$setdata{notmailed};
			printf(LOGFILE
			join("",map({"%$_->{size}$_->{type}"} @reportstyle),"\n"), @setdata{map{$_->{name}}@reportstyle});
		}
	}

	$jobbag->{__job}{total_sets} = $summarydata{mailed};

	# stream totals in footer.
	printf(LOGFILE
		join("",map({"%$_->{size}$_->{type}"} @reportstyle),"\n"),
		@summarydata{map{$_->{name}}@reportstyle});
	close LOGFILE or Utils::JEF_Exception::terminate("Unable to open $logFile for writing: $!");
}

1;
