package Reports::CopyReport;

use base qw(GenericProcessor);
use strict;
use NA::Std::EmailXmlUtils;
use File::Copy;
use FileHandle;
use CcsCommon;
use Data::Dumper;

sub generateEmail {
    my( $this, $jobbag ) = @_;

    my $contract = $jobbag->{'__config'}->{'job'}->{'job_code'}; 
    my $run = $jobbag->{'__run_params'}->{'run_num'};
    my $report_email_list = $contract eq '145BM0001' || $contract eq '145BM0002' ? 'bmo_xaa_report_email' : 'bmo_generic_report_email';
    my $recipients = CcsCommon::get_setting('reports', $report_email_list);
    my $emailFileName = "MailSummaryReport_${contract}_${run}.txt";
    my $subject = "Contract $contract Run $run Files Processed";
    
    # if more than one file was processed join the list
    my $data_files = $jobbag->{__print_file}{file};
	if (ref $jobbag->{__print_file}{file} eq 'ARRAY'){
		$data_files = join (",\n", @{$jobbag->{__print_file}{file}});
    }
    
    my $body = "This email is to inform you that Contract $contract Run $run has finished.\nFile(s): $data_files\nSets: $jobbag->{__data}{accumulated_set_no}";
    NA::Std::EmailXmlUtils::createEmailXml($recipients, $subject, $body, $emailFileName);

}

sub run {
	my ($this, $jobbag) = @_;

	my $mail_summary_report = NA::Std::Utils::getLogFileName($jobbag, 'MailSummaryReport', 'txt');

	return if $jobbag->{ec_details}->{'sample'};
	
	print "Sending email\n";
	$this->generateEmail($jobbag);

}

1;
