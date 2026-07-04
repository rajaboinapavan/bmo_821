#!c:/perl5.10.1/bin/perl.exe

use 5.010;

use strict;
use warnings;

################################################################################

use lib "$ENV{CCS_RESOURCE}";
use lib_CCS(
	GPD       => '3.00',
	JEF       => '1.00',
	JobEngine => '1.00',
	local =>
		[ 'Modules', 'Modules/Processors', 'Modules/BusinessRules', 'Modules/Renders', 'Modules/Utils', '../Common', ],
	others => [
		$ENV{CCS_RESOURCE} . '/Regional',
		$ENV{CCS_RESOURCE} . '/Regional/<lib_ccs_region>/Finalist/5.10',
		$ENV{CCS_RESOURCE} . '/Regional/NA/Library',

	],
);

use NA::Std::Paths;
use XML::Twig;

use NA::PostProcess::CheckUniqueVerify;
use Utilities;

################################################################################
## Perl Includes...

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent   = 1;
use DateTime;
use Time::HiRes;

################################################################################
## BGR/GPD Includes...
use GPD;
use JEF;
use Admin::Aardvark;

################################################################################

autoflush STDOUT, 1;
autoflush STDERR, 1;

################################################################################

use ProcServices::ContractServer qw{$PkgDir};
exit ProcServices::ContractServer->main( handler => \&execute );

################################################################################

sub help {
	print <<"HELP";
	
You asked for help by using --help

There are extra options that can/should be added in the Aa Automated Job Details as Extra Arguments 
and can/should be added to the command line during development or manual processing

  	--threshhold <integer> used to override argument in Utilities::motus
  	--sleep  <integer> used to override argument in Utilities::motus
  	--alert_every <integer> used to override argument in Utilities::motus
  	--corropack_group <string> used to populate PO XML xpath Path/CorrespondenceDetails/Group, this is only needed during the conversion step
  	--corropack_product <string> used to populate PO XML xpath Path/CorrespondenceDetails/Product, this is only needed during the conversion step
  	--corropack_id <string> used to populate PO XML xpath Path/CorrespondenceDetails/Correspondence_Pack_Id, this is only needed during the conversion step
  	--autoprocess this takes no value and is added when a job runs through ProcCentral
		\$jobbag->{__run_params}{is_autoprocess} will be set to 1 if used
		can be helpful for not deleting, moving files and other things during development
		add --autoprocess to the command line during development and check to see how/where this is currently implemented in the contract code
	--convert this takes no value and is to be added when a job is only doing file conversion
	--doc_comp this takes no value and is to be added when a job is only doing document composition

HELP

	exit 0;
}

sub execute {
	my $t0 = [ Time::HiRes::gettimeofday() ];

	my $jef = JEF->new("$PkgDir/Config/Config.jef.xml");

	if ( $jef->get_params('help') ) {
		help();
	}

	my $data_dir = $jef->get_params('data_dir');

	my $archive = $jef->get_params('archive');

	my $config = $jef->get_config();

	my $data_files = [ Utilities::getUnignoredFiles() ];

	# need to work out when to use which JEF components based on the --doc_comp or --convert command line options

	if ( $jef->get_params('doc_comp') or $jef->get_params('po_sample_mode') ) {

		# make sure these stay in this order, changing the order can have an unexpected outcome
		$jef->add_pre_processor('SampleSetup');
		$jef->add_pre_processor('JobEngine_PreProcessor');
		$jef->add_pre_processor('GetGraphicsLibsPreProcessor');
		$jef->add_pre_processor('DocCompPreProcessor_UPSandFedExCounts');

		# the order that the pre and post processors are added is important here
		if ( !$jef->get_params('po_sample_mode') ) {

			$jef->add_pre_processor('DocCompPreProcessor');
			$jef->add_post_processor('DocCompPostProcessor');

			if ( !$jef->get_params('skip_dup_check_checking') ) {
				$jef->add_post_processor('NA::PostProcess::CheckUniqueVerify');
			}

		}

		foreach my $filename ( @{$data_files} ) {
			$jef->add_data_reader(
				'JobEngineXMLReader', "$data_dir/$filename",
				$config->{data_reader}{set_xpath},
				$config->{data_reader}{set_id_xpath}
			);
		}

		$jef->add_rendering('DocComp');

	}
	elsif ( $jef->get_params('convert') ) {

		$jef->add_pre_processor('ConverterPreProcessor');
		if ( !$jef->get_params('skip_dup_check_checking') ) {
			$jef->add_pre_processor('DupCheckPreProcessor');
		}
		$jef->add_business_rule('ConverterBusinessRules');

		my @new_id_files = ();

		while ( @{ $jef->get_params('data_files') } ) {
			my $orig_data_file = shift @{ $jef->get_params('data_files') };
			my $id_xml_file = create_pain001_with_unique_ids( $data_dir, $orig_data_file );
			push @new_id_files, $id_xml_file;
		}

		@{ $jef->get_params('data_files') } = @new_id_files;

		foreach my $filename ( @{ $jef->get_params('data_files') } ) {
			$jef->add_data_reader(
				'NA::DataReaders::TagNameDrivenLibXMLReader',
				"$data_dir/$filename",
				'tagsDesired' => [ 'GrpHdr', 'PmtInf', 'Dbtr', 'DbtrAcct', 'DbtrAgt', 'CdtTrfTxInf' ]
			);

		}

		$jef->add_rendering('Converter');
		$jef->add_post_processor('ConverterPostProcessor');

	}
	else {
		Utils::JEF_Exception::terminate(
'--doc_comp or --convert were not part of the command line or Extra Arguments in the Aa Automated Job Details'
		);
	}

	$jef->execute();

	printf( "Total run duration %.2f seconds\n", Time::HiRes::tv_interval($t0) );
	$main::progress_file_obj->progress(100) if defined $main::progress_file_obj;
	return 0;
}

sub create_pain001_with_unique_ids {
	my ( $data_dir, $in_xml_file ) = @_;

	( my $out_xml_file = $in_xml_file ) =~ s/\.XML/\.ID.XML/i;

	open( my $OUT, '>', "$data_dir\\$out_xml_file" ) or die "Unable to open $out_xml_file for writing\n";

	my $end_to_end_id;

	my $t = XML::Twig->new(
		twig_roots => {
			'Document/CstmrCdtTrfInitn/PmtInf/CdtTrfTxInf/PmtId/EndToEndId' => sub {
				my ( $str, $elt, $ccs_trans_id );
				$str = $_->text;
				$end_to_end_id->{$str}++;
				$ccs_trans_id = $str . '_' . sprintf( "%05d", $end_to_end_id->{$str} );
				$elt = XML::Twig::Elt->new();
				$elt->set_tag("CCS_EndToEndID");
				$elt->set_text($ccs_trans_id);
				$_->print;
				$elt->print;

				return;
			},
		},
		twig_print_outside_roots => $OUT,
		pretty_print             => 'none',
	);
	$t->parsefile("$data_dir\\$in_xml_file");

	return $out_xml_file;

}

