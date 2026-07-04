package Reports::EmailToAM;

use strict;
use Data::Dumper;
use CcsSmtp;
use CcsCommon;

sub send_email {
    my($this) = @_;

    my $email_list = 'bmo_am_note_email';
    my $addresses = CcsCommon::get_setting('EMAIL', $email_list);    
    my $subject = "WARNING - 145BM0008 BMO Harris Bank NA DDA Non and Image Bank 29";
    my $body = "This job contains no hopper calls, please verify selection criteria is accurate.";

	my %mail = (
		to => [ $addresses ],
		from => '#USCTSEncompassSupport@computershare.com', 
		subject => $subject,
		body => [ $body ],
		attachments => [],
	);
	           
    my $ret = CcsSmtp::SendMail(\%mail);
    print "CcsSmtp::SendMail() returned ".(Dumper $ret);
}

1;
