package ProductRunner;
use strict;
use Cwd;
use Data::Dumper;

use lib "$ENV{CCS_RESOURCE}/Regional/";
use NA::Std::Paths;

use lib 'Modules';

use Logger::Log;
use JEF;
use Carp;
use CcsCommon;
use Admin::Aardvark;
use Utilities;

use NA::Std::Graphics;
use Readonly;
Readonly our $BMO_GRAPHICS_PATH => CcsCommon::get_setting('graphics', 'bmo_path');

$SIG{__DIE__}  = sub { confess "@_" unless $^S; };
$SIG{__WARN__} = sub { confess "@_" unless $^S; }; 

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent = 1;
autoflush STDOUT, 1;

sub new {
	my ($object) = @_;
	my $class = ref($object) || $object;
	my $this = {};
	Log->print("BMO Product runner called via:\n$^X $0 @ARGV");
	bless($this, $class);

    return $this;
}


=pod
    Subroutine: getRequiredPostProcessors

    Description: Get the required post processors and their arguments.

    Arguments: none

    Returns: The required preprocessor module and their arguments.

=cut

sub getRequiredPostProcessers {
    my( $this ) = @_;
    return (
    			{ 'module' => 'Reports::MailSummary', 'arguments' => [] }
     );
}

sub getRequiredPreProcessors {
	my( $this ) = @_;
	return (
	         {'module' => 'NA::PreProcess::Region', 'arguments' => []},
	       );
}

sub getRequiredBusinessRules {
	my( $this ) = @_;
	return;
}

=pod

    Subroutine: addProcessingModule

    Description: Add a processing module to your contract.

    Arguments: $type - type of processing module to add
               $module - the name of the module to add
               @args - hash, array, or undefined that can include additional arguments
                       to pass over to your processing module

    Returns: none

    USAGE: $runner->addProcessingModule('businessRules', 'MyBusinessRules', @myBusinessRuleArgs );

=cut

sub addProcessingModule {
    my( $this, $type, $module, @args ) = @_;
    my %types = map { $_ => 1 } ( 'businessRule', 'gpdRendering', 'preProcess', 'postProcess' );
    if( ! $types{$type} ) {
        Log->do_confess("$type unknown processing module type");
    }
    push( @{ $this->{processingModules}->{$type}}, { 'module' => $module, 'arguments' => \@args } );
}

=pod
    Subroutine: _getProcessingModules

    Description: Do not use this outside of this package. Returns the
                 processing modules and their arguments of a specific type.

    Arguments: $type

    Returns: None
=cut

sub _getProcessingModules {
    my( $this, $type, $sort ) = @_;
    ##
    ## preProcess and postProcess are optional if the
    ##
    my %defaults = ( 'businessRule' => [{'module' => 'ProductBusinessRules', 'arguments' => []} ],
                     'gpdRendering' => [{'module' => 'ProductGpdRender', 'arguments' => [] }],
                   );

    $defaults{'preProcess'} =  ( -e "$this->{productPath}/Modules/ProductPreProcessor.pm" )  ? [{ 'module' => 'ProductPreProcessor', 'arguments' => [] }] : undef;
    $defaults{'postProcess'} = ( -e "$this->{productPath}/Modules/ProductPostProcessor.pm" ) ? [{ 'module' => 'ProductPostProcessor', 'arguments' => [] }] : undef;

    my $processor = $this->{'processingModules'}->{$type} || $defaults{$type} || [];

    if( $type eq 'postProcess' ) {
        unshift(@$processor, $this->getRequiredPostProcessers() );
    }
    elsif( $type eq 'preProcess' ) {
		unshift(@$processor, $this->getRequiredPreProcessors() );
    }
    elsif( $type eq 'businessRules' ) {
		unshift(@$processor, $this->getRequiredBusinessRules() );
    }

    return $processor;
}

=pod

    Subroutine:  setDataFileFactory

    Description: Use this if Data_Factory.pm will not suit your needs and you have to replace
                 or overwrite it.

    Arguments:   $factory - Your data factory name.


    Returns:     None

=cut

sub setDataFileFactory {
    my( $this, $factory ) = @_;
    $this->{dataFileFactory} = $factory;
}

=pod

    Subroutine: _getDataFileFactory

    Description: You should not need to use this.  Return the name of the data factory
                 module for the current process.

    Arguments: None

    Returns: The name of the data factory module for the current object.

=cut

sub _getDataFileFactory {
    my( $this ) = @_;
    return $this->{dataFileFactory} || 'NA::DataReaders::Data_Factory';
}

=pod

	Subroutine: getProductDirectory

	Description: Get the product directory

	Arguments: none

	Returns: Product directory

=cut

sub getProductDirectory {
	my( $this ) = @_;
	return "$ENV{CCS_RESOURCE}/Regional/NA/Products";
}

=pod

    Subroutine: runProduct

    Description: Run the product.

    Arguments:     $naProductPathName - The name of the product that you want to run.
                                        There must be a directory for the product at
                                        $CCS_RESOURCE/Regional/NA/Products/

                   $contractConfig -    Name of the config file for the current contract.
                                        This only needs to be specified if the file is not
                                        named contract.xml.

                   %args           -    Any additional arguments that you want your
                                        contracts to pass onto the product.  This should be
                                        used if you want to have your product do slightly
                                        different things for one contract vs another.  Such
                                        as generate Canadian vs US documents.

    Returns: None

=cut

sub runProduct {
    my($this, $contractConfig ) = @_;

    $contractConfig ||= 'contract.xml';
	my $fqContractConfig = -e $contractConfig ? $contractConfig : cwd () . '/' . $contractConfig;
    my $jef = JEF->new( $fqContractConfig );

	my $naProductPathName = $jef->{__config}->{job}->{product_runner_name};
	my $productDir = $this->getProductDirectory();
    my $productPath = "$productDir/$naProductPathName";

    $this->{productPath} = $productPath;
    unshift( @INC, "$productPath/Modules" );

    addGraphicsPath("$ENV{CCS_RESOURCE}/Regional/NA/sourceGraphics");
    addGraphicsPath("$productPath/sourceGraphics");
    addGraphicsPath($BMO_GRAPHICS_PATH);

    my %jobparams = CcsCommon::parse_job_params(@ARGV);

    my $progressPercentObject;
    my $finalistPostProcessingTimePercent = 0;
    my $finaliseSamplesTimePercent = 0;
    my $postProcessingPercent = 10;
    if( defined $jobparams{progress_file} && defined $jobparams{data_files_size} ) {
        if( ! defined $jef->{__config}{job}{skip_finalise_samples} ) {
            $finaliseSamplesTimePercent = 15;
            $postProcessingPercent += $finaliseSamplesTimePercent;
        }
        if( !defined $jobparams{extra} || !grep { /--skip_finalist/ } @{ $jobparams{extra} } ) {
            $finalistPostProcessingTimePercent = 15;
            $postProcessingPercent += $finalistPostProcessingTimePercent;
        }
        $progressPercentObject = Admin::Aardvark->new_progress(
                                    progress_file    => $jobparams{progress_file},
                                    data_files_size  => $jobparams{data_files_size},
                                    gpd_post_proc_pc => $postProcessingPercent,
        );
    }
    $jef->add_global('progressPercentObject', $progressPercentObject);
    $jef->add_global('finalistPostProcessingTimePercent',$finalistPostProcessingTimePercent);
    $jef->add_global('finaliseSamplesTimePercent', $finaliseSamplesTimePercent);
    $jef->add_global('postProcessingPercent', $postProcessingPercent);
    $jef->add_global('datafileBusinessRuleRenderingPercent', 100 - $postProcessingPercent );

    foreach my $preProcessor ( @{ $this->_getProcessingModules('preProcess') }) {
        next unless $preProcessor;
        $jef->add_pre_processor($preProcessor->{module}, @{$preProcessor->{arguments}});
    }

	# the index file process only needs to preprocess, no need to do anything else, so set that in the config
	if (!defined $jef->{__config}{job}{preprocess_only} || $jef->{__config}{job}{preprocess_only} != 1){

	    foreach my $businessRule ( @{ $this->_getProcessingModules('businessRule') } ) {
	        next unless $businessRule;
	        $jef->add_business_rule( $businessRule->{module}, @{$businessRule->{arguments}} );
	    }

	    my $dataFactory = $this->_getDataFileFactory();

	    eval("use $dataFactory");
	    if( $@ ) {
	        Log->do_confess("Error loading $dataFactory -- $@");
	    }
	    my $factory = $dataFactory->new();
	    $factory->createDataReaders($jef);

	    foreach my $gpdRender ( @{ $this->_getProcessingModules('gpdRendering') } ) {
	        next unless $gpdRender;
	        $jef->add_rendering( $gpdRender->{module}, @{$gpdRender->{arguments}} );
	    }

	    foreach my $postProcessor ( @{ $this->_getProcessingModules('postProcess', $jef->{__config}->{job}->{postal_sort}) } ) {
	        next unless $postProcessor;
	        $jef->add_post_processor($postProcessor->{module}, @{$postProcessor->{arguments}});
	    }
	}
	elsif (defined $jef->{__config}{job}{postprocess_email} and $jef->{__config}{job}{postprocess_email} == 1){
        $jef->add_post_processor('Reports::EmailReport');
	}

    if( defined $progressPercentObject ) {
        $progressPercentObject->progress(1);
    }

    $jef->execute();

    if( defined $progressPercentObject ) {
        $progressPercentObject->progress(100);
    }

}

1;
