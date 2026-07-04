package Utilities;

=head1 NAME

Utilities - Shared utils


=head1 DESCRIPTION

The name says it all

=head1 BUGS/QUIRKS

=head1 COPYRIGHT

Copyright 2010 (C), Computershare Document Services. All Rights Reserved

=cut

use lib "$ENV{CCS_RESOURCE}/Global/JEF/ver/1.00";
use base qw(GenericProcessor);
use strict;
use warnings;
use Data::Dumper;
use File::Copy;
use Cwd;
use Getopt::Long qw(:config pass_through);

use lib "$ENV{CCS_RESOURCE}/Regional/";    #Wr-409
use NA::Std::Paths;
use AdmXml;
use Sort::GPD;

use lib "$ENV{CCS_RESOURCE}" . '/Regional';
use NA::Std::ZipUtils;

use Logger::Log;
use Time::localtime;                       #WR-271a
use File::stat;                            #WR-271a

use lib "$ENV{CCS_RESOURCE}/Global/GPD/Ver/3.00";    #WR-409
use GPD;                                             #WR-271a

use NA::Std::EmailXmlUtils;

sub load_documents {
	###############################################
	# DO NOT ADD DOCUMENTS FOR CONTRACT 145BM0007 #
	###############################################
	my $documents = {
		'DDA311LL' => {
			'doc_id'      => 'LET3.1BMO',
			'description' => 'STOP RENEWAL LETTER',
		},
		'XVRLETER' => {
			'doc_id'      => 'LET3.2BMO',
			'description' => 'TELEPHONE BANKING',
		},
		'XKOCLUL' => {
			'doc_id'      => 'LET3.3BMO',
			'description' => 'COLLECTION LETTER',
		},
		'XRM877WLDOM' => {
			'doc_id'      => 'LET3.4BMO',
			'description' => 'WELCOME LETTER - DOMESTIC',
		},
		'PCLLETTERS' => {
			'doc_id'      => 'LET3.5BMO',
			'description' => 'PCL LETTER',
		},
		'XRM877WLFOR' => {
			'doc_id'      => 'LET3.6BMO',
			'description' => 'WELCOME LETTER - FOREIGN',
		},
		'MLSSEL' => {
			'doc_id'      => 'LET3.10BMO',
			'description' => 'SHORT PAYMENT LETTER',
		},
		'MLSSUL' => {
			'doc_id'      => 'LET3.10BMO',
			'description' => 'UNAPPLIED LETTER',
		},
		'MLSPMI' => {
			'doc_id'      => 'LET3.11BMO',
			'description' => 'PMI LETTER',
		},
		'MLSWEA' => {
			'doc_id'      => 'LET3.12BMO',
			'description' => 'WEA LETTER',
		},
		'MLSWEL' => {
			'doc_id'      => 'LET3.13BMO',
			'description' => 'WEL LETTER',
		},
		'FPI1PRT' => {
			'doc_id'      => 'NOT2.49BMO',
			'description' => 'FORCED INSURANCE LETTERS',
		},
		'PRT40DAY' => {
			'doc_id'      => 'NOT2.50BMO',
			'description' => '40 DAY NOTIFICATION',
		},
		'XAA_INV' => {
			'doc_id'      => 'NOT2.1BMO',
			'description' => 'XAA INVOICES',
		},
		'MNETSTOCK' => {
			'doc_id'      => 'NOT2.6BMO',
			'description' => 'ST W-4P NOTICES',
		},
		'HBMGFT_ADV' => {
			'doc_id'      => 'NOT2.6BMO',
			'description' => 'ST W-4P NOTICES',
		},
		'HBMNET' => {
			'doc_id'      => 'NOT2.6BMO',
			'description' => 'ST W-4P NOTICES',
		},
		'PEPAUTO' => {
			'doc_id'      => 'NOT2.7BMO',
			'description' => 'PEP ADVICES',
		},
		'PEPMAN' => {
			'doc_id'      => 'NOT2.8BMO',
			'description' => 'PEP ADVICES',
		},
		'XSTB314' => {
			'doc_id'      => 'NOT2.9BMO',
			'description' => 'ST DOSCLOSURE NOTICES BANK 31',
		},
		'XSTB304' => {
			'doc_id'      => 'NOT2.10BMO',
			'description' => 'ST DISCLOSURE NOTICES BANK 30',
		},
		'XSTB294' => {
			'doc_id'      => 'NOT2.11BMO',
			'description' => 'ST APPLICATION NOTICES',
		},
		'XSTB31C' => {
			'doc_id'      => 'NOT2.12BMO',
			'description' => 'ST W-4P NOTICES',
		},
		'XSTB29C' => {
			'doc_id'      => 'NOT2.13BMO',
			'description' => 'ST W-4P NOTICES',
		},
		'XSTHB-29N' => {
			'doc_id'      => 'NOT2.14BMO',
			'description' => 'ST APPLICATION NOTICES',
		},
		'XSTHB-41PE' => {
			'doc_id'      => 'NOT2.15BMO',
			'description' => 'ST APPLICATION NOTICES',
		},
		'XSTB30N' => {
			'doc_id'      => 'NOT2.16BMO',
			'description' => 'ST APPLICATION NOTICES',
		},
		'XSTB31N' => {
			'doc_id'      => 'NOT2.17BMO',
			'description' => 'ST APPLICATION NOTICES',
		},
		'XIMMAILM' => {
			'doc_id'      => 'NOT2.18BMO',
			'description' => 'BANK 29 OD NOTICES',
		},
		'XIMMAILN' => {
			'doc_id'      => 'NOT2.19BMO',
			'description' => 'BANK 28 OD NOTICES',
		},
		'XIMMAILB' => {
			'doc_id'      => 'NOT2.20BMO',
			'description' => 'MAIL DEPOSIT NOTICES',
		},
		'XIMMAILC' => {
			'doc_id'      => 'NOT2.21BMO',
			'description' => 'WIRE TRANSFER AND MISC ADVICES',
		},
		'XIMNOTOR' => {
			'doc_id'      => 'LET3.9BMO',
			'description' => 'NOTICES LETTER',
		},
		'XIMNOTOD' => {
			'doc_id'      => 'NOT2.51BMO',
			'description' => 'OD NOTICES',
		},
		'XIMNOTNSF' => {
			'doc_id'      => 'NOT2.51BMO',
			'description' => 'OD NOTICES',
		},
		'XAMNOTIL' => {
			'doc_id'      => 'NOT2.22BMO',
			'description' => 'AM NOTICES ILLINOIS',
		},
		'XAMNOT' => {
			'doc_id'      => 'NOT2.23BMO',
			'description' => 'AM APPL NOTICES COMM BANKS',
		},
		'XAMNOTPD2' => {
			'doc_id'      => 'NOT2.23BMO',
			'description' => 'AM APPL NOTICES COMM BANKS',
		},
		'XAMNOT9' => {
			'doc_id'      => 'NOT2.24BMO',
			'description' => 'AM APPL NOTICES COMM BANKS',
		},
		'MLSDAILY' => {
			'doc_id'      => 'NOT2.25BMO',
			'description' => 'CONSUMER LENDING CENTER',
		},
		'XCLBL31B' => {
			'doc_id'      => 'NOT2.26BMO',
			'description' => 'BLST LOAN ACCOUNTING',
		},
		'XCLB29N2' => {
			'doc_id'      => 'NOT2.27BMO',
			'description' => 'LOAN ACCOUNTING PAYMENT NOTICES',
		},
		'XCLB29S2' => {
			'doc_id'      => 'NOT2.29BMO',
			'description' => 'LOAN ACCOUNTING COMBINES STATEMENT',
		},
		'XCLB29N4' => {
			'doc_id'      => 'NOT2.28BMO',
			'description' => 'LOAN ACCOUNTING PAST DUE NOTICES',
		},
		'SBAHBM1' => {
			'doc_id'      => 'NOT2.30BMO',
			'description' => 'SAFE DEPOSIT NOTICE',
		},
		'SBAHBM2' => {
			'doc_id'      => 'NOT2.31BMO',
			'description' => 'SAFE DEPOSIT ADVICE',
		},
		'DDA0037' => {
			'doc_id'      => 'NOT2.35BMO',
			'description' => 'EXCEPTION UNIT',
		},
		'SBAB29NO' => {
			'doc_id'      => 'NOT2.36BMO',
			'description' => 'SAFE DEPOSIT NOTICE - DRILL NOTICES',
		},
		'SBAHBMM' => {
			'doc_id'      => 'NOT2.37BMO',
			'description' => 'SAFE DEPOSIT',
		},
		'XCLBL31MC' => {
			'doc_id'      => 'NOT2.38BMO',
			'description' => 'BLST LOAN ACCOUNTING',
		},
		'XCLB31N' => {
			'doc_id'      => 'NOT2.39BMO',
			'description' => 'CL APPLICATION REPORTS',
		},
		'XCLB29S4' => {
			'doc_id'      => 'NOT2.40BMO',
			'description' => 'LOAN ACCOUNTING PAYMENT NOTICES',
		},
		'XAMNOTPD' => {
			'doc_id'      => 'NOT2.41BMO',
			'description' => 'AM APPL NOTICES COMM BANKS - Past Dues',
		},
		'XAMNOTMA' => {
			'doc_id'      => 'NOT2.42BMO',
			'description' => 'AM APPL NOTICES COMM BANKS - Maturity',
		},
		'XSTB30C' => {
			'doc_id'      => 'NOT2.43BMO',
			'description' => 'ST W-4P NOTICES',
		},
		'XSTHB-412' => {
			'doc_id'      => 'NOT2.44BMO',
			'description' => 'Required Minimum Distribution Notice',
		},
		'XAM429' => {
			'doc_id'      => 'NOT2.45BMO',
			'description' => 'Mortgage Notice',
		},
		'MICRTST' => {
			'doc_id'      => 'NOT2.46BMO',
			'description' => 'MICR Testing',
		},
		'BPIMICR' => {
			'doc_id'      => 'NOT2.46BMO',
			'description' => 'MICR Testing',
		},
		'HELOC' => {
			'doc_id'      => 'NOT2.47BMO',
			'description' => 'HELOC Notice',
		},
		'CFPB' => {
			'doc_id'      => 'NOT2.48BMO',
			'description' => 'CFPB Notice',
		},
		'BDBFraud' => {
			'doc_id'      => 'NOT2.54BMO',
			'description' => 'Fraud Notice',
		},
		'XAM003CLU' => {
			'doc_id'      => 'RPT1.1BMO',
			'description' => 'AM LOAN APPLICATION REPORT',
		},
		'CTXHB-OS' => {
			'doc_id'      => 'RPT1.2BMO',
			'description' => 'OUT OF STATE REGIONAL REPORTS',
		},
		'DISRPTS' => {
			'doc_id'      => 'RPT1.3BMO',
			'description' => 'CHEQUE PROCESSING TECH RESOURCES',
		},
		'IASHACT' => {
			'doc_id'      => 'RPT1.4BMO',
			'description' => 'INT ACCOUNTING REPORTS',
		},
		'IASICL' => {
			'doc_id'      => 'RPT1.5BMO',
			'description' => 'INTERNATION CASH LETTER REPORT',
		},
		'ILD02' => {
			'doc_id'      => 'RPT1.6BMO',
			'description' => 'BMO CHICAGO TREASURY REPORT',
		},
		'HBIBU005' => {
			'doc_id'      => 'RPT1.7BMO',
			'description' => 'BMO REG REPORTS - Chicago 6',
		},
		'GLMB050' => {
			'doc_id'      => 'RPT1.8BMO',
			'description' => 'LETTERS OF CREDIT DIVISION',
		},
		'HBIBU002' => {
			'doc_id'      => 'RPT1.9BMO',
			'description' => 'BMO REG REPORTS',
		},
		'HBIBU003' => {
			'doc_id'      => 'RPT1.10BMO',
			'description' => 'PROCUREMENT OPERATIONS REPORT',
		},
		'CLS0091' => {
			'doc_id'      => 'RPT1.13BMO',
			'description' => 'INSTITUTIONAL MARKET REPORT',
		},
		'XCLBLS9' => {
			'doc_id'      => 'RPT1.15BMO',
			'description' => 'ARM SCHEDULED BALANCE REPORT',
		},
		'CLS0330' => {
			'doc_id'      => 'RPT1.17BMO',
			'description' => 'COMMERCIAL MISD-MARKET REPORT',
		},
		'CLS0303' => {
			'doc_id'      => 'RPT1.18BMO',
			'description' => 'COMMERCIAL MISD-MARKET REPORT',
		},
		'CLS0306' => {
			'doc_id'      => 'RPT1.20BMO',
			'description' => 'CAROLE ROSA-FLOSNIK REPORT',
		},
		'CLS0327' => {
			'doc_id'      => 'RPT1.21BMO',
			'description' => 'HARRIS WINNETKA',
		},
		'CLS0325' => {
			'doc_id'      => 'RPT1.22BMO',
			'description' => 'HARRIS NAPERVILLE',
		},
		'CLS0325A' => {
			'doc_id'      => 'RPT1.23BMO',
			'description' => 'HARRIS ROSELLE',
		},
		'CLS0087' => {
			'doc_id'      => 'RPT1.24BMO',
			'description' => 'HARRIS BARRINGTON',
		},
		'CLS0328' => {
			'doc_id'      => 'RPT1.25BMO',
			'description' => 'HARRIS BARRINGTON',
		},
		'CLS0093' => {
			'doc_id'      => 'RPT1.26BMO',
			'description' => 'HARRIS 111 MONROE',
		},
		'XCLB52' => {
			'doc_id'      => 'RPT1.27BMO',
			'description' => 'HARRIS JOLIET',
		},
		'CLS0104' => {
			'doc_id'      => 'RPT1.28BMO',
			'description' => 'PRIVATE BANK 111',
		},
		'CLS0126' => {
			'doc_id'      => 'RPT1.29BMO',
			'description' => 'PRIVATE BANK 111',
		},
		'CLS0323' => {
			'doc_id'      => 'RPT1.30BMO',
			'description' => 'HARRIS PALATINE',
		},
		'DDA0026' => {
			'doc_id'      => 'RPT1.32BMO',
			'description' => 'KURT DAHL REPORT',
		},
		'DDA1119E' => {
			'doc_id'      => 'RPT1.33BMO',
			'description' => 'MIKE LIPINSKI CASH MANAGEMENT',
		},
		'DDA0003' => {
			'doc_id'      => 'RPT1.34BMO',
			'description' => 'SAIC',
		},
		'DDA0004' => {
			'doc_id'      => 'RPT1.36BMO',
			'description' => 'PATTY VARELLA REPORT',
		},
		'DDA0006' => {
			'doc_id'      => 'RPT1.37BMO',
			'description' => 'MIKE LIPINSKI REPORT',
		},
		'GLMB085' => {
			'doc_id'      => 'RPT1.38MO',
			'description' => 'TRUST OPS UNIT',
		},
		'GLMRPTS_B' => {
			'doc_id'      => 'RPT1.39MO',
			'description' => 'GENERAL LEDGER REPORTS',
		},
		'GLMB042' => {
			'doc_id'      => 'RPT1.40MO',
			'description' => 'EXULT BMO PAYROLL',
		},
		'GLMB052' => {
			'doc_id'      => 'RPT1.41MO',
			'description' => 'INT L CASH LTRS ADJ UNIT',
		},
		'GLMB066' => {
			'doc_id'      => 'RPT1.42MO',
			'description' => 'GTM CLIENT BILLING',
		},
		'GLMRPTS_A2' => {
			'doc_id'      => 'RPT1.43MO',
			'description' => 'GENERAL LEDGER REPORTS',
		},
		'HRM1000F' => {
			'doc_id'      => 'RPT1.44MO',
			'description' => 'ACCOUNTING NANCY HARRISON',
		},
		'ARP4109' => {
			'doc_id'      => 'RPT1.50BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'CTXHB-RR' => {
			'doc_id'      => 'RPT1.51BMO',
			'description' => 'REGIONAL REPORTS',
		},
		'CTXNOT' => {
			'doc_id'      => 'RPT1.52BMO',
			'description' => 'OUT OF STATE REGIONAL NOTICES',
		},
		'CLS0299' => {
			'doc_id'      => 'RPT1.53BMO',
			'description' => 'COMMERCIAL MISD-MARKET REPORT',
		},
		'CLS0104RM' => {
			'doc_id'      => 'RPT1.54BMO',
			'description' => 'PRIVATE BANK 111',
		},
		'HBIBU004' => {
			'doc_id'      => 'RPT1.56BMO',
			'description' => 'LETTERS OF CREDIT DIVISION',
		},
		'MLSUSERA' => {
			'doc_id'      => 'RPT1.57BMO',
			'description' => 'HARRIS BANK CONSUMER LENDING CENTER',
		},
		'HBIBU001' => {
			'doc_id'      => 'RPT1.58BMO',
			'description' => 'B Parks',
		},
		'ARP4109L' => {
			'doc_id'      => 'RPT1.60BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP4209' => {
			'doc_id'      => 'RPT1.61BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP4209L' => {
			'doc_id'      => 'RPT1.62BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5111' => {
			'doc_id'      => 'RPT1.63BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5381' => {
			'doc_id'      => 'RPT1.64BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5381' => {
			'doc_id'      => 'RPT1.64BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5517' => {
			'doc_id'      => 'RPT1.65BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5544' => {
			'doc_id'      => 'RPT1.66BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5547' => {
			'doc_id'      => 'RPT1.67BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'DISCNTRL' => {
			'doc_id'      => 'RPT1.68BMO',
			'description' => 'DIS CONTROL CLERK',
		},
		'CLS0238' => {
			'doc_id'      => 'RPT1.69BMO',
			'description' => 'COMMERCIAL MISD-MARKET REPORT',
		},
		'CLS0076' => {
			'doc_id'      => 'RPT1.70BMO',
			'description' => 'DORA ARAIZA REPORT',
		},
		'CLS0119' => {
			'doc_id'      => 'RPT1.71BMO',
			'description' => 'CHERYLE WITTERT REPORT',
		},
		'CLS0120' => {
			'doc_id'      => 'RPT1.72BMO',
			'description' => 'JOHN RASKE REPORT',
		},
		'CLS0123' => {
			'doc_id'      => 'RPT1.73BMO',
			'description' => 'VICKY ARROYO REPORT',
		},
		'CLS0148' => {
			'doc_id'      => 'RPT1.74BMO',
			'description' => 'MARY PAT BITTMAN REPORT',
		},
		'CLS0149' => {
			'doc_id'      => 'RPT1.75BMO',
			'description' => 'PAM DEAN REPORT',
		},
		'CLS0211' => {
			'doc_id'      => 'RPT1.76BMO',
			'description' => 'ROBERT LEACH REPORT',
		},
		'CLS0239' => {
			'doc_id'      => 'RPT1.77BMO',
			'description' => 'RAY WHITAKER REPORT',
		},
		'CLS0241' => {
			'doc_id'      => 'RPT1.78BMO',
			'description' => 'KERI MINIHAN REPORT',
		},
		'CLS0298' => {
			'doc_id'      => 'RPT1.79BMO',
			'description' => 'DEBORAH FORD REPORT',
		},
		'CLS0315' => {
			'doc_id'      => 'RPT1.80BMO',
			'description' => 'ERIC ROBISON REPORT',
		},
		'CLS0323A' => {
			'doc_id'      => 'RPT1.81BMO',
			'description' => 'BETH WOLFE REPORT',
		},
		'XCL111A' => {
			'doc_id'      => 'RPT1.82BMO',
			'description' => 'JANE HANES/CARL JENKINS REPORT',
		},
		'ARP302H' => {
			'doc_id'      => 'RPT1.83BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302JI' => {
			'doc_id'      => 'RPT1.84BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302J' => {
			'doc_id'      => 'RPT1.85BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302K' => {
			'doc_id'      => 'RPT1.86BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302L' => {
			'doc_id'      => 'RPT1.87BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302M' => {
			'doc_id'      => 'RPT1.88BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302T' => {
			'doc_id'      => 'RPT1.89BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP30214' => {
			'doc_id'      => 'RPT1.90BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP3101A' => {
			'doc_id'      => 'RPT1.91BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302G' => {
			'doc_id'      => 'RPT1.92BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5191' => {
			'doc_id'      => 'RPT1.93BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5550' => {
			'doc_id'      => 'RPT1.94BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302B' => {
			'doc_id'      => 'RPT1.96BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302C' => {
			'doc_id'      => 'RPT1.97BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302D' => {
			'doc_id'      => 'RPT1.98BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302E' => {
			'doc_id'      => 'RPT1.99BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302F' => {
			'doc_id'      => 'RPT2.00BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP30213' => {
			'doc_id'      => 'RPT2.02BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP302I' => {
			'doc_id'      => 'RPT2.01BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP30215' => {
			'doc_id'      => 'RPT2.03BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5053' => {
			'doc_id'      => 'RPT2.17BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5092' => {
			'doc_id'      => 'RPT2.18BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5253' => {
			'doc_id'      => 'RPT2.19BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP5521' => {
			'doc_id'      => 'RPT2.20BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'CTXHB095' => {
			'doc_id'      => 'RPT2.25BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP7901' => {
			'doc_id'      => 'RPT2.26BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'CLS0257' => {
			'doc_id'      => 'RPT2.27BMO',
			'description' => 'CLS REPORT',
		},
		'CLS0323C' => {
			'doc_id'      => 'RPT2.28BMO',
			'description' => 'CLS REPORT',
		},
		'DDA0027' => {
			'doc_id'      => 'RPT2.29BMO',
			'description' => 'REPORT',
		},
		'CLS0129' => {
			'doc_id'      => 'RPT2.30BMO',
			'description' => 'REPORT',
		},
		'MLSUSER1' => {
			'doc_id'      => 'RPT2.31BMO',
			'description' => 'MLS REPORT',
		},
		'ARP5549' => {
			'doc_id'      => 'RPT2.32BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'ARP30299' => {
			'doc_id'      => 'RPT2.33BMO',
			'description' => 'ARP UNIT REPORTS',
		},
		'GLMPADIL' => {
			'doc_id'      => 'RPT2.34BMO',
			'description' => 'REPORTS',
		},
		'GLMSUBS' => {
			'doc_id'      => 'RPT2.41',
			'description' => 'REPORTS',
		},
		'GLMB033' => {
			'doc_id'      => 'RPT2.42',
			'description' => 'REPORTS',
		},
		'GLMB42A' => {
			'doc_id'      => 'RPT2.43',
			'description' => 'REPORTS',
		},
		'GLMAUDT' => {
			'doc_id'      => 'RPT2.44',
			'description' => 'REPORTS',
		},
		'HRM1200A' => {
			'doc_id'      => 'RPT2.45',
			'description' => 'REPORTS',
		},
		'GLMRPTSA' => {
			'doc_id'      => 'RPT2.46',
			'description' => 'REPORTS',
		},
		'XIMSOCB' => {
			'doc_id'      => 'RPT2.47',
			'description' => 'REPORTS',
		},
		'ARP3102A' => {
			'doc_id'      => 'RPT2.48',
			'description' => 'REPORTS',
		},
		'APR300233' => {
			'doc_id'      => 'RPT2.49',
			'description' => 'REPORTS',
		},
		'ARP4112L' => {
			'doc_id'      => 'RPT2.50',
			'description' => 'REPORTS',
		},
		'ARP4112' => {
			'doc_id'      => 'RPT2.51',
			'description' => 'REPORTS',
		},
		'ARP3106A' => {
			'doc_id'      => 'RPT2.52',
			'description' => 'REPORTS',
		},
		'ARP4203L' => {
			'doc_id'      => 'RPT2.53',
			'description' => 'REPORTS',
		},
		'ARP4302' => {
			'doc_id'      => 'RPT2.54',
			'description' => 'REPORTS',
		},
		'ARP4203' => {
			'doc_id'      => 'RPT2.55',
			'description' => 'REPORTS',
		},
		'ARP4103L' => {
			'doc_id'      => 'RPT2.56',
			'description' => 'REPORTS',
		},
		'ARP4103' => {
			'doc_id'      => 'RPT2.57',
			'description' => 'REPORTS',
		},
		'ARP3110A' => {
			'doc_id'      => 'RPT2.58',
			'description' => 'REPORTS',
		},
		'ARP3109A' => {
			'doc_id'      => 'RPT2.58',
			'description' => 'REPORTS',
		},
		'CLS0329' => {
			'doc_id'      => 'RPT2.59',
			'description' => 'REPORTS',
		},
		'GLMRPTS_A' => {
			'doc_id'      => 'RPT2.60',
			'description' => 'REPORTS',
		},
		'HRM1000G' => {
			'doc_id'      => 'RPT2.61',
			'description' => 'REPORTS',
		},
		'ARP302R' => {
			'doc_id'      => 'RPT2.62',
			'description' => 'REPORTS',
		},
		'CLS0089' => {
			'doc_id'      => 'RPT2.63',
			'description' => 'REPORTS',
		},
		'CLS0177' => {
			'doc_id'      => 'RPT2.64',
			'description' => 'REPORTS',
		},
		'CLS0112' => {
			'doc_id'      => 'RPT2.65',
			'description' => 'REPORTS',
		},
		'CLS0240' => {
			'doc_id'      => 'RPT2.66',
			'description' => 'REPORTS',
		},
		'CLS0302' => {
			'doc_id'      => 'RPT2.67',
			'description' => 'REPORTS',
		},
		'ARP3103A' => {
			'doc_id'      => 'RPT2.68',
			'description' => 'REPORTS',
		},
		'ARP3104A' => {
			'doc_id'      => 'RPT2.69',
			'description' => 'REPORTS',
		},
		'ARP3105A' => {
			'doc_id'      => 'RPT2.70',
			'description' => 'REPORTS',
		},
		'ARP3107A' => {
			'doc_id'      => 'RPT2.71',
			'description' => 'REPORTS',
		},
		'DDAHAR06B' => {
			'doc_id'      => 'STMT1.1BMO',
			'description' => 'DDA CORP STMT BANK 28',
		},
		'DDAHAR25' => {
			'doc_id'      => 'STMT1.2BMO',
			'description' => 'DDA CORP STMT BANK 28',
		},
		'DDAHAR00' => {
			'doc_id'      => 'STMT1.3BMO',
			'description' => 'DDA CORP STMT BANK 28',
		},
		'DDAHAR02' => {
			'doc_id'      => 'STMT1.4BMO',
			'description' => 'DDA CORP STMT BANK 28',
		},
		'DDAHAR07' => {
			'doc_id'      => 'STMT1.5BMO',
			'description' => 'DDA CORP STMT BANK 28',
		},
		'DDAHAR06A' => {
			'doc_id'      => 'STMT1.6BMO',
			'description' => 'DDA CORP STMT BANK 28',
		},
		'DDAHAR08' => {
			'doc_id'      => 'STMT1.7BMO',
			'description' => 'DDA CORP STMT BANK 28',
		},
		'XSTSOCS' => {
			'doc_id'      => 'STMT1.8BMO',
			'description' => 'IRA STATEMENTS',
		},
		'XIM' => {
			'doc_id'      => 'STMT1.9',
			'description' => 'BANK 29 IMAGE STATEMENTS',
		},
		'XSC' => {
			'doc_id'      => 'STMT1.10',
			'description' => 'BANK 29 NON IMAGE STATEMENTS',
		},
		'XAA_AA' => {
			'doc_id'      => 'STMT1.11BMO',
			'description' => 'XAA ACCOUNT ANALYSIS STATEMENTS',
		},
		'ARP3002A' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002D' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002E' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002F' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002G' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002H' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002I' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002J' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002K' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002L' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002M' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP3002Q' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP300213' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP300214' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP300299' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP300230' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP300231' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP300232' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'ARP300233' => {
			'doc_id'      => 'STMT1.12BMO',
			'description' => 'ARP UNIT STATEMENTS',
		},
		'XTXRBS029' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXRBS' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXBREC' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXCREC' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXDIVR' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX4000' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXMISC' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXNEC' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXOIDR' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX1042' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX1042B' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX1042C' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX1042D' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX1042S' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXRECB' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXRECC' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXSARE' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXAREC' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX1098' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTXQREC' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX98RE' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX98ES' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX99SA' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX98SA' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX1099B' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX1099R' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'W8W9' => {
			'doc_id'      => 'TAX1.2BMO',
			'description' => 'W8W9 DOCS',
		},
		'XTX5498SA' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX5498ES' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX5498RE' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'XTX5498N' => {
			'doc_id'      => 'TAX1.1BMO',
			'description' => 'TAX DOCS',
		},
		'REMOVAL' => {
			'doc_id'      => 'NOT2.55BMO',
			'description' => 'ACCOUNT RESTRICTION REMOVAL LETTER',
		},
		'RESTRICTION' => {
			'doc_id'      => 'NOT2.56BMO',
			'description' => 'ACCOUNT RESTRICTION LETTER',
		},
	};

	return $documents;
}

sub verify_single_sets {
	my ($jobbag) = @_;

	my $pdfPageCount = @{
		Shared::Image::read_info(
			CcsCommon::get_setting( 'graphics', 'bmo_path' ) . '\\' . $jobbag->{__pdf_graphics}{graphic},
			'', '1.6' )
	};

	if ( $jobbag->{__data}{accumulated_set_no} != $pdfPageCount ) {
		Utils::JEF_Exception::terminate( 'Number of sets = '
				. $jobbag->{__data}{accumulated_set_no}
				. "\nPDF pages = $pdfPageCount\n The numbers should match.\n" );
	}

	return;
}

sub create_radar_wo {
	my ($jobbag) = @_;

	my $radarHandler = Canton_All_Radar->new();
	$radarHandler->init();

	my $wo = $radarHandler->CreateWorkOrder(
		rmemail       => $jobbag->{__job_contact_info}[0]{email},
		companycode   => $jobbag->{__ass}{data}{job}{client_code},
		clientname    => $jobbag->{__ass}{data}{job}{client_name},
		producttype   => $jobbag->{__config}{job}{product_type},
		estvolume     => $jobbag->{__data}{accumulated_set_no},
		branchid      => 25,
		mailhouse     => 13,
		radar_company => 2
	);

	$wo =~ s/^\s+//;
	$wo =~ s/\s+$//;

	if ( $wo !~ /^[0-9A-F]{1,3}\d{2}\w{2}\d{2}$/ ) {
		Utils::JEF_Exception::terminate( 'Proper RADAR Work Order not returned ' . $wo );
	}

	foreach my $stream ( sort( keys %{ $jobbag->{__streams} } ) ) {

		my $filename = $jobbag->{__ass}{data}{gpds}{$stream}{adm}{stream}{name};

		next if ( not -e $filename );

		AdmXml::update_xml( "$filename.adm.xml", { job => { work_order => $wo } } );

	}

	return;
}

sub delete_pdf_update_graphics_folder {
	Utils::JEF_Exception::terminate(
		'delete_pdf_update_graphics_folder is no longer used, all graphics are included in the archive');

	return;
}

sub paper_insert_weight {
	my ( $set_weight, $envelopes ) = @_;

	# we need to remove the env weight from the set weight in order to
	# calculate the streaming based on the weight of just the paper and insert
	# just being paranoid about the envelope, should never happen, but make sure there is only 1

	if ( scalar keys %{$envelopes} > 1 ) {
		Utils::JEF_Exception::terminate('Should only have 1 envelope\outer');
	}
	elsif ( scalar keys %{$envelopes} == 0 ) {
		return ($set_weight);
	}
	else {
		foreach my $item ( keys %{$envelopes} ) {

			# should only ever be here one time so just return when we have it
			return ( $set_weight - $envelopes->{$item}{grams} );
		}
	}

	return;
}

sub batch_breaks {
	my ($filename) = @_;

	Sort::GPD->run($filename);

	my $msg = "Breaking $filename into weight based batches\n";
	my @batchBreaks;
	my $results = UtilsGpdReaders::get_sets_info( filename => $filename, incl_weight => 1, incl_stocks => 1 );

	my $previousOunces  = -1;
	my $batchBreakCount = 0;
	for ( my $i = 1 ; $i <= $results->{num_sets} ; $i++ ) {
		my $grams  = $results->{weight}->[$i];
		my $stocks = $results->{stocks}->[$i];
		my $ounces = _getOunceRangeForUSPSFromGrams($grams);

		if ( $stocks->{'001CD80009'} || $stocks->{'001CD80072'} || $ounces ne $previousOunces ) {
			$batchBreakCount++;
			push( @batchBreaks, { set => $i, desc => "Batch Break $batchBreakCount for $ounces" } );
		}
		$previousOunces = $ounces;
	}

	if (@batchBreaks) {
		AdmXml::update_xml( "$filename.adm.xml", { batch_breaks => \@batchBreaks } );
	}

	return;
}

sub _getOunceRangeForUSPSFromGrams {
	my ($grams) = @_;
	##
	## We may have to add capabilities for 'flats'
	## though technically the logic below
	## should sufficiently break batches for the print rooms
	## without causing a need to generate different logic below
	## for flat streams.
	##

	my $roundedOz = int( $grams / 28.35 + 1 );

	if ( !$grams ) {
		$roundedOz = 'Unknown weight in oz';
	}
	elsif ( $roundedOz > 13 ) {
		if ( $roundedOz < 16 ) {
			$roundedOz = 'Up to 1 lb zone';
		}
		elsif ( $roundedOz < 32 ) {
			$roundedOz = 'Up to 2 lb zone';
		}
		elsif ( $roundedOz < 48 ) {
			$roundedOz = 'Up to 3 lb zone';
		}
		elsif ( $roundedOz < 64 ) {
			$roundedOz = 'Up to 4 lb zone';
		}
		elsif ( $roundedOz < 80 ) {
			$roundedOz = 'Up to 5 lb zone';
		}
		elsif ( $roundedOz < 85 ) {
			$roundedOz = 'Up to 5 lb 5 oz zone';
		}
		else {
			$roundedOz = 'Greater than 5 lb 5 oz zone';
		}
	}
	else {
		my $lowRangeSide = $roundedOz - 1;
		$roundedOz = "$lowRangeSide - $roundedOz oz";
	}

	return $roundedOz;
}

sub copy_or_move_file {
	Utils::JEF_Exception::terminate('copy_or_move_file has been replaced with motus, use the new motus function');

	return;
}

sub data_file_path {

	# get the typical processing path that we see when jobs process using Aa Auto Processing
	my $cwd = getcwd();

	# if this is not processing from a developers machines there should be directories
	# with 'processing' and 'run' in the name, otherwise just return and stage the data files
	# to the graphics dir of the processing dir
	return if ( $cwd !~ /processing.+run\d+/i );

	my @cwd_dirs = split( '/', reverse($cwd), 2 );
	my $run_dir = reverse( $cwd_dirs[1] ) . '_data';
	return $run_dir;

}

sub zipFiles {
	my ( $zipFile, @files ) = @_;

	my $success = 0;
	my $exe     = NA::Std::Utils::get7zipExecutablePath();
	my $cmd     = "$exe a -w -tZip $zipFile " . join ' ', @files;
	for my $tries ( 0 .. 3 ) {
		local $| = 1;
		my $msg = "EXECUTING: $cmd\n";
		print $msg;

		# allow zipFile or files with spaces to process properly
		if ( system( $exe, 'a', '-w', '-tZip', $zipFile, @files ) == 0 ) {
			$success = 1;
			last;
		}
	}
	if ( !$success ) {
		die "Error executing $cmd: $?\n";
	}
}

# broken Latin for motion; this does a move or copy, FOREVER!
sub motus {
	my %args = @_;

	my $action =
		defined $args{'action'}
		? $args{'action'}
		: Utils::JEF_Exception::terminate('no action specified for motus');

	my $source =
		defined $args{'source'}
		? $args{'source'}
		: Utils::JEF_Exception::terminate('no source specified for motus');

	my $target =
		defined $args{'target'}
		? $args{'target'}
		: Utils::JEF_Exception::terminate('no target specified for motus');

	my %actions = (
		move => {
			ref  => sub        { return move $_[0], $_[1]; },
			args => [ $source, $target ],
		},
		copy => {
			ref  => sub        { return copy $_[0], $_[1]; },
			args => [ $source, $target ],
		},
	);

	if ( not -f $source ) {
		Utils::JEF_Exception::terminate("motus $action: source '$source' is not a file!");
	}

	# not sure if we should check the target

	my ( undef, $caller_file, $caller_line ) = caller();

	if ( exists $actions{$action} ) {
		repeat(
			do            => $actions{$action}{'ref'},
			args          => $actions{$action}{'args'},
			caller_file   => $caller_file,
			caller_line   => $caller_line,
			error_handler => sub { Utils::JEF_Exception::terminate(@_) },
			threshhold    => $args{threshhold},
			sleep         => $args{sleep},
			alert_every   => $args{alert_every},
		);
	}
	else {
		Utils::JEF_Exception::terminate("Unrecognized motus action: '$action'!");
	}

	return;
}

# take a code reference and repeat until successful
sub repeat {
	my %args = @_;

	# error default to die
	my $error_handler =
		defined $args{'error_handler'}
		? $args{'error_handler'}
		: sub { die @_ };

	my $code_ref = $args{'do'} or $error_handler->('repeat() called without \'do\' argument!');

	my $threshhold =
		( defined $args{'threshhold'} and $args{'threshhold'} !~ /\D/ )
		? $args{'threshhold'}
		: 100;

	my $sleep =
		( defined $args{'sleep'} and $args{'sleep'} !~ /\D/ )
		? $args{'sleep'}
		: 30;

	my $alert_every =
		( defined $args{'alert_every'} and $args{'alert_every'} !~ /\D/ )
		? $args{'alert_every'}
		: 20;

	my $ref_args =
		defined $args{'args'}
		? $args{'args'}
		: [];

	my ( $caller_file, $caller_line );
	if ( not defined $args{'caller_file'} or not defined $args{'caller_line'} ) {
		( undef, $caller_file, $caller_line ) = caller();
	}
	else {
		( $caller_file, $caller_line ) = ( $args{'caller_file'}, $args{'caller_line'} );
	}

	my $times = 0;

	while ( not $code_ref->(@$ref_args) ) {
		my $error = $!;    # hmm, maybe not..
		$times++;

		if ( $threshhold and $times > $threshhold ) {
			$error_handler->(
				"repeat() threshhold met; giving up action called from $caller_file, line $caller_line; Error: $error");
		}
		elsif ( $alert_every and 0 == ( $times % $alert_every ) ) {

			# alert, maybe to the trace file, maybe some other way
			Log->do_warn("repeat() action called from $caller_file, line $caller_line failed $times times: $error");
		}

		# else, try again

		sleep $sleep;
	}

	return;
}

sub change_directory {
	my %args = @_;
	my ( undef, $caller_file, $caller_line ) = caller();

	my $dir =
		defined $args{'dir'}
		? $args{'dir'}
		: Utils::JEF_Exception::terminate(
		"No directory specified for change_directory at $caller_file line $caller_line");

	repeat(
		do          => sub { chdir $_[0]; },
		args        => [$dir],
		caller_file => $caller_file,
		caller_line => $caller_line,
	);

	return;
}

sub index_preprocess_file_stager {
	my ( $jobbag, $pdf, $dataDir, $file ) = @_;

	my %args;
	GetOptions( \%args, 'threshhold=s', 'sleep=s', 'alert_every=s' );

	my $pdf_path  = CcsCommon::get_setting( 'graphics', 'bmo_path' );
	my $emtex_dir = CcsCommon::get_setting( 'emtex',    'bmo_out' );

	Log->do_warn("Staging PDF $pdf to $pdf_path");

	my $attempts = 105;
	for ( my $tries = 1 ; $attempts >= $tries ; $tries++ ) {
		if ( -e "$emtex_dir\\$pdf" ) {

			# First we want to check for a PDF in the Emtex folder.
			# A new Emtex PDF should be used instead of an existing PDF in the graphics folder.
			# If the PDF is in the Emtex folder move it to the graphics folder.

			motus(
				action      => 'move',
				source      => "$emtex_dir\\$pdf",
				target      => "$pdf_path\\$pdf",
				threshhold  => $args{threshhold},
				sleep       => $args{sleep},
				alert_every => $args{alert_every},
			);

			Log->do_warn("PDF moved");
			last;
		}
		elsif ( -e "$pdf_path\\$pdf" ) {

			# If the PDF is not in the Emtex folder check to see if the PDF is already in the graphics folder,
			# we are just going to rerun the same PDF as is.
			# If there is a need to use a new PDF used it should have been reran through Emtex
			# and the PDF will be in the Emtex folder above and we would not hit this condition.
			Log->do_warn("Found existing PDF $pdf_path\\$pdf");
			last;
		}
		else {
			# If the PDF is not in the Emtex or graphic folder wait a while and continue the loop.
			# At this point we are just waiting for Emtex to spit the PDF out.
			# After a certain number of loops we are going to exit and will hit the terminate exception
			# a few lines below
			Log->do_warn("Waiting for PDF $pdf to show up in $emtex_dir\nMove attempt $tries of $attempts");
			sleep(60);
		}
	}

	# If we made it through the for loop above check to see if the PDF has been staged, if not, terminate.
	if ( !-e "$pdf_path\\$pdf" ) {
		Utils::JEF_Exception::terminate( "$pdf is not in the Emtex folder and is not already staged in $pdf_path\n"
				. "Drop $file into the appropriate Emtex folder and create the PDF before requeing this failed process"
		);
	}

	if ( $jobbag->{__config}{job}{staging_location} ) {

		# copy the pdf from Canton to Burr Ridge
		Log->do_warn(
			'$jobbag->{__config}{job}{staging_location} should no longer be used, remove this from the config XML.'
				. "\n$pdf is not being staged to a print site." );
	}

	# copy the djde from the holding folder to the geGraphics folder
	motus(
		action      => 'copy',
		source      => "$dataDir\\$file",
		target      => "$pdf_path\\$file",
		threshhold  => $args{threshhold},
		sleep       => $args{sleep},
		alert_every => $args{alert_every},
	);

	return;
}

sub doc_comp_preprocess_file_stager {
	my ( $jobbag, $file_base, $file_ext ) = @_;

	# the pdf and xerox print file should be in the location defined
	# in CcsCommon::get_setting('graphics', 'bmo_path')
	# the pdf is used as a graphic, the xerox print file is going to the data folder at $data_file_path
	# if the $data_file_path is not defined handle the files as graphics so they get archived somewhere
	my $graphic_path = CcsCommon::get_setting( 'graphics', 'bmo_path' );
	my $data_file_path = Utilities::data_file_path();

	my $pdf_graphic = $file_base . '.pdf';
	my $print_file  = $file_base . $file_ext;

# these backer_graphics should probably be made more generic to avoid having them staged like this, probably a list of
# sort some would be better, but there are too many live docs and xml configs for each contract for this change to be made now
	NA::Std::Graphics::prepareGraphic( $jobbag->{__config}{job}{instream_letter} )
		if $jobbag->{__config}{job}{instream_letter};
	NA::Std::Graphics::prepareGraphic( $jobbag->{__config}{job}{backer_graphic} )
		if $jobbag->{__config}{job}{backer_graphic};
	NA::Std::Graphics::prepareGraphic( $jobbag->{__config}{job}{backer_graphic_1099INT} )
		if $jobbag->{__config}{job}{backer_graphic_1099INT};
	NA::Std::Graphics::prepareGraphic($pdf_graphic);

	if ( defined $data_file_path ) {
		if ( !copy( "$graphic_path//$print_file", $data_file_path ) ) {
			Utils::JEF_Exception::terminate("Copying of $graphic_path//$print_file to $data_file_path failed");
		}
	}
	else {
		NA::Std::Graphics::prepareGraphic($print_file);
	}

	$jobbag->{__pdf_graphics}{graphic} = $pdf_graphic;
	$jobbag->{__print_file}{file}      = $print_file;

	return;
}

### WR-271a,d
sub get_file_date_time {
	my ( $jobbag, $file_name ) = @_;
	my $dir_file    = CcsCommon::get_setting( 'GENERAL', 'datain_folder' ) . '\\BMO_145BM\\Archive\\' . $file_name;
	my @date_string = localtime( stat("$dir_file")->mtime );
	my $sec         = sprintf( '%02d', $date_string[0][0] );
	my $min         = sprintf( '%02d', $date_string[0][1] );
	my $hour        = sprintf( '%02d', $date_string[0][2] );
	my $day         = sprintf( '%02d', $date_string[0][3] );
	my $mon         = sprintf( '%02d', $date_string[0][4] + 1 );
	my $year        = sprintf( '%02d', $date_string[0][5] + 1900 );
	my $date_time   = "$year$mon$day $hour:$min:$sec";

	$jobbag->{__bmo_file}{name} = $file_name;
	$jobbag->{__bmo_file}{date} = $date_time;

	return;
}

sub add_reporting_set_tags {
	my ( $jobbag, $insert_stock_string ) = @_;
	my $name_file = undef;
	my $date_time = undef;

	$name_file = $jobbag->{__bmo_file}{name};
	$date_time = $jobbag->{__bmo_file}{date};

	if ( not defined $name_file ) {
		Utils::JEF_Exception::terminate("BMO_OriginalFileName not set in jobbag");
	}
	if ( not defined $date_time ) {
		Utils::JEF_Exception::terminate("BMO_FileReceivedDateTime not set in jobbag");
	}
	add_set_tags(
		BMO_OriginalFileName     => $name_file,
		BMO_FileReceivedDateTime => $date_time,
		BMO_InsertStocks         => $insert_stock_string,
	);

	return;
}

## WR-292
sub gpd_to_pdf {

	my ($jobbag) = @_;
	my %args;
	my ( @pdfs, @tokens );
	GetOptions( \%args, 'ftp_out_path=s', 'create_pdf=s' );

	unless ( exists $args{ftp_out_path} && exists $args{create_pdf} ) {
		print
"Utilities::gpd_to_pdf: one or more of the expected arguments for ftp_out_path or create_pdf was not initialized\n";
		return ( undef, undef );    # don't return anything to caller
	}

	# set ftp path
	my $ftp_path = CcsCommon::get_setting( 'FTP_Path', 'base_ftp_path' ) . '\\' . $args{ftp_out_path};

	# check to see if the arguments passed in are valid
	if ( $args{create_pdf} eq "NONE" ) {
		print "Utilities::gpd_to_pdf: --create_pdf = NONE so no pdfs will be created\n";
		return ( undef, undef );    # don't return anything to caller
	}
	else {
		# string of NOTs are comma-delimited passed from Aardvark into the script
		# but the string may or may not include leading or trailing whitespace
		# adding defensive programming to avoid a crash
		@tokens = split( /\s*,\s*/, $args{create_pdf} );

		if ( $args{create_pdf} eq "ALL" ) {
			foreach my $stream ( keys %{ $jobbag->{__streams} } ) {

				# get run number for gpd file
				my $run_num = $jobbag->{__run_params}{run_num};

				my $gpd_file = "$stream\_${run_num}.gpd";

				if ( not -e "$gpd_file" ) {
					print "'skipping $gpd_file does not exist\n";
					next;
				}
				else {
					my $cmd = "$ENV{CCS_RESOURCE}\\Global\\Scripts\\g2p.cmd $gpd_file";
					system($cmd);
					if ($?) {
						Utils::JEF_Exception::terminate("Something unexpected happened with $cmd\n$?");
					}
					# if it didn't crash, add the newly created pdf to the array
					push( @pdfs, "$stream\_${run_num}.pdf" );
				}
			}    # end foreach
		}         # end if for ALL
		else {    # process the list of NOT
			      # get run number for gpd file
			my $run_num = $jobbag->{__run_params}{run_num};

			foreach my $token (@tokens) {
				foreach my $stream ( keys %{ $jobbag->{__streams} } ) {

					my $gpd_file = "$stream\_${run_num}.gpd";

					if ( not -e "$gpd_file" ) {
						print "skipping $gpd_file does not exist\n";
						next;
					}

					if ( $gpd_file !~ /$token/ ) {
						print "skipping '$gpd_file' does not need PDF created\n";
						next;
					}
					else {
						print "Converting $gpd_file to PDF...\n";
						my $cmd = "$ENV{CCS_RESOURCE}\\Global\\Scripts\\g2p.cmd $gpd_file";
						system($cmd);
						if ($?) {
							Utils::JEF_Exception::terminate("Something unexpected happened with $cmd\n$?");
						}

						my $pdf_file = "$stream\_${run_num}.pdf";
						if ( -e $pdf_file ) {
							push( @pdfs, "$pdf_file" );
							print "$pdf_file pushed into \@pdfs\n";
						}
					}
				}    # end inner foreach
			}    # end outer foreach
		}    # end inner else
	}    # end outer else

	# return list of pdfs populated from either ALL or the default partial list of NOTs
	return ( \@pdfs, $ftp_path );    # return a reference to @pdfs and the scalar ftp path to caller
}

sub getUnignoredFiles {
	my %job_params = CcsCommon::parse_job_params(@ARGV);
	my @files;
	if ( defined $job_params{data_files} ) {
		@files = @{ $job_params{data_files} };
	}

	if ( $job_params{extra} ) {
		for ( my $i = 0 ; $i <= $#{ $job_params{extra} } ; $i++ ) {
			if ( $job_params{extra}[$i] =~ /--ignore/ && $job_params{extra}[ $i + 1 ] ) {
				my $ignorefile = $job_params{extra}[ $i + 1 ];
				@files = grep { $_ !~ /$ignorefile/i } @files;
			}
		}
	}

	my @sorted_files = sort { $a cmp $b } @files;

	return @sorted_files;
}

sub generate_email {
	my %args = @_;

	NA::Std::EmailXmlUtils::createEmailXml( $args{recipients}, $args{subject}, $args{email_body},
		$args{email_file_name}, $args{attachments} );

	my $email_xml_file = "$args{email_file_name}_1_email.xml";
	NA::Std::EmailXmlUtils::sendEmailForAnEmailXmlFile($email_xml_file);

	Log->print("Email recipients: $args{recipients}\nSubject: $args{subject}\nBody: $args{email_body}\n");

	return;

}

###
1;
