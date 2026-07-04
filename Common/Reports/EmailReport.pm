package Reports::EmailReport;

use base qw(GenericProcessor);
use strict;
use warnings;
use NA::Std::EmailXmlUtils;
use File::Copy;
use FileHandle;
use CcsCommon;
use Data::Dumper;
use Getopt::Long qw(:config pass_through);

sub generateEmail {
	my ( $this, $jobbag ) = @_;
	my %opts;

	# get email list passed in from Aa -email_add in extra parameter field
	GetOptions( \%opts, "email_add=s" );

	my $contract      = $jobbag->{'__config'}->{'job'}->{'job_code'};
	my $recipients    = $opts{email_add};
	my $emailFileName = $jobbag->{client_report_file_name};
	my $emailFilePath = $jobbag->{client_report_file_path};
	my $subject       = "Client Summary Report";
	my $body = "This email is to inform you that\nFile: " . $jobbag->{__run_params}{data_files}[0] . " has processed\n";
	NA::Std::EmailXmlUtils::createEmailXml( $recipients, $subject, $body, $emailFileName,
		"$emailFilePath\\$emailFileName" );

	my $emailXmlFile = "${emailFileName}_1_email.xml";
	NA::Std::EmailXmlUtils::sendEmailForAnEmailXmlFile($emailXmlFile);

	return;
}

sub run {
	my ( $this, $jobbag ) = @_;

	return if $jobbag->{ec_details}->{'sample'};
	$this->generateEmail($jobbag);

	return;

}

1;
