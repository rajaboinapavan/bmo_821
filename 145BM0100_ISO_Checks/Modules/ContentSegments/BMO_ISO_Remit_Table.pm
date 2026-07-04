package ContentSegments::BMO_ISO_Remit_Table;

## no critic
sub get_module_signature {
	return 'e3d6e538c36ef0d5225ae71ec4520989';
}    # automatically added by dependency script - please do not touch
## use critic

use 5.010;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(
	render
	_get_remittance_table
	_populate_remittance_table
	_render_table
	get_segment_info);

use lib "$ENV{CCS_RESOURCE}";
use lib_CCS GPD => '3.00', JobEngine => '1.00';

use base qw(BaseComplexSegment);
use Data::Dumper;
use GPD;
use Number::Format;

use Markup::Common;

my $ypos     = 0;
my $cur_page = 0;

## no critic
sub prepare {
	my ($this) = shift;
	my %props = @_;

	$this->height( $props{height} );
	$this->width( $props{width} );

	return 1;
}
## use critic

sub render {
	my ( $this, %args ) = @_;
	my $set         = $args{set};
	my $height      = $this->height;
	my $width       = $this->width;
	my $custom_data = $this->custom_data();
	my $pdf_summary_table;

	if ( not( $custom_data and keys %$custom_data ) ) {
		$pdf_summary_table = $this->_get_remittance_table();
		$this->custom_data( { table => $pdf_summary_table } );
		$this->_populate_remittance_table( $pdf_summary_table, $set );
	}
	else {
		$pdf_summary_table = $custom_data->{table};
	}

	my $table_emitted = $this->_render_table( $pdf_summary_table, $width, $height );

	if ( $table_emitted == 0 ) {
		return { completed => 0 };
	}
	else {
		$custom_data->{table} = undef;
		return { completed => 1 };
	}
}

sub _get_remittance_table {
	my $record = Markup::RespecTable::RowFormat->new(
		row_values => {
			num_of_cells    => 5,
			height          => 1,
			flexible_height => 1,
		},
		cell_defaults => {
			width                => 1,
			horizontal_alignment => 'L',
			vertical_alignment   => 'M',
			markup_call          => {
				type => 'put',
				font => 'arialmt+10',
			},
			padding => {
				top   => 0.1,
				left  => 0.2,
				right => 0.2,
			},
		},
	);

	$record->set_cell_values(
		cell   => 1,
		width  => 2.8448,
		border => {
			sides => ['right'],
			line  => 0.02,
		},
		markup_call => {
			type => 'put',
			font => 'arialmt+10',
		},
		allow_out_of_markup_area => 1,
	);

	$record->set_cell_values(
		cell   => 2,
		width  => 3.81,
		border => {
			sides => ['right'],
			line  => 0.02,
		},
		markup_call => {
			type    => 'wrap',
			font    => 'arialmt+10',
			leading => '0.295',
		},
	);

	$record->set_cell_values(
		cell   => 3,
		width  => 3.81,
		border => {
			sides => ['right'],
			line  => 0.02,
		},
		markup_call => {
			type    => 'wrap',
			font    => 'arialmt+10',
			leading => '0.295',
		},
		horizontal_alignment => 'R',
	);

	$record->set_cell_values(
		cell   => 4,
		width  => 4.0894,
		border => {
			sides => ['right'],
			line  => 0.02,
		},
		markup_call => {
			type    => 'wrap',
			font    => 'arialmt+10',
			leading => '0.295',
		},
		horizontal_alignment => 'R',
	);

	$record->set_cell_values(
		cell                 => 5,
		width                => 4.3434,
		horizontal_alignment => 'R',
		markup_call          => {
			type    => 'wrap',
			font    => 'arialmt+10',
			leading => '0.295',
		},
	);

	my $one_time_header = Markup::RespecTable::RowFormat->new(
		row_values => {
			num_of_cells    => 1,
			height          => 1,
			flexible_height => 1,
		},
		cell_defaults => {
			width                => 10,
			horizontal_alignment => 'L',
			vertical_alignment   => 'T',
			markup_call          => {
				type => 'segment',
			},
			padding => {
				top    => 0.1,
				bottom => 0.1,
				left   => 0.1,
			},
		},
	);

	##WR 695
	my $one_time_footer = Markup::RespecTable::RowFormat->new(
		row_values => {
			num_of_cells    => 1,
			height          => 1,
			flexible_height => 1,
		},
		cell_defaults => {
			width                => 19,
			horizontal_alignment => 'C',
			vertical_alignment   => 'T',
			markup_call          => {
				type => 'segment',
			},
			padding => {
				top    => 0.1,
				bottom => 0.1,
				left   => 0.1,
			},
		},
	);

	my $paginating_header = $one_time_header->clone();
	my $paginating_footer = $one_time_footer->clone();

	my $every_time_header = Markup::RespecTable::RowFormat->new(
		row_values => {
			num_of_cells    => 5,
			height          => 1,
			flexible_height => 1,
		},
		cell_defaults => {
			width                => 1,
			horizontal_alignment => 'C',
			vertical_alignment   => 'M',
			markup_call          => {
				type    => 'wrap',
				font    => 'arial-boldmt+10',
				leading => '0.4',
			},
		},
	);

	$every_time_header->set_cell_values(
		cell   => 1,
		width  => 2.8448,
		border => {
			sides => [ 'top', 'bottom', 'inner', 'right' ],
			line  => 0.04,
		},
	);

	$every_time_header->set_cell_values(
		cell   => 2,
		width  => 3.81,
		border => {
			sides => [ 'top', 'bottom', 'inner', 'left', 'right' ],
			line  => 0.04,
		},
	);

	$every_time_header->set_cell_values(
		cell   => 3,
		width  => 3.81,
		border => {
			sides => [ 'top', 'bottom', 'inner', 'left', 'right' ],
			line  => 0.04,
		},
	);

	$every_time_header->set_cell_values(
		cell   => 4,
		width  => 4.0894,
		border => {
			sides => [ 'top', 'bottom', 'inner', 'left', 'right' ],
			line  => 0.04,
		},
	);

	$every_time_header->set_cell_values(
		cell   => 5,
		width  => 4.3434,
		border => {
			sides => [ 'top', 'bottom', 'inner', 'left', ],
			line  => 0.04,
		},
	);

	# every_time_footer for bottom table line
	my $every_time_footer = Markup::RespecTable::RowFormat->new(
		row_values => {
			num_of_cells    => 5,
			height          => 0,
			flexible_height => 1,
		},
		cell_defaults => {
			width                => 0,
			horizontal_alignment => 'C',
			vertical_alignment   => 'M',
			markup_call          => {
				type    => 'wrap',
				font    => 'arial-boldmt+10',
				leading => '0.4',
			},
		},
	);

	$every_time_footer->set_cell_values(
		cell   => 1,
		width  => 2.8448,
		border => {
			sides => [ 'top', ],
			line  => 0.04,
		},
	);

	$every_time_footer->set_cell_values(
		cell   => 2,
		width  => 3.81,
		border => {
			sides => [ 'top', ],
			line  => 0.04,
		},
	);

	$every_time_footer->set_cell_values(
		cell   => 3,
		width  => 3.81,
		border => {
			sides => [ 'top', ],
			line  => 0.04,
		},
	);

	$every_time_footer->set_cell_values(
		cell   => 4,
		width  => 4.0894,
		border => {
			sides => [ 'top', ],
			line  => 0.04,
		},
	);

	$every_time_footer->set_cell_values(
		cell   => 5,
		width  => 4.3434,
		border => {
			sides => [ 'top', ],
			line  => 0.04,
		},
	);

	my $pdf_summary_table = Markup::RespecTable->new(
		table_name => 'Table',
		formats    => {
			one_time_header   => $one_time_header,
			paginate_header   => $paginating_header,
			paginate_footer   => $paginating_footer,
			every_time_header => $every_time_header,
			record            => $record,
			every_time_footer => $every_time_footer,
		},
	);

	return $pdf_summary_table;
}

sub _populate_remittance_table {
	my ( $this, $pdf_summary_table, $set ) = @_;

	my $title_bar = new_segment();
	pos_box(
		xpos       => 0,
		ypos       => 0,
		xsize      => 5,
		ysize      => 0.8,
		fill_color => 0,
	);

	put( "ACCOUNT DETAILS", 0, 0.7, 'arial-boldmt+12', 'L', 5 );
	end_segment;

	my $continue_bar = new_segment();
	pos_box(
		xpos       => 0,
		ypos       => 0,
		xsize      => 5,
		ysize      => 0.8,
		fill_color => 0,
	);

	put( "CONTINUE", 0, 0.7, 'arial-boldmt+12', 'L', 5 );
	end_segment;

	##WR 695
	my $footer_bar = new_segment();
	pos_box(
		xpos       => 0,
		ypos       => 0,
		xsize      => 5,
		ysize      => 0.8,
		fill_color => 0,
	);

	put( "Additional details on reverse", 0, 0.7, 'arial-boldmt+10', 'L', 5 );
	end_segment;

	$pdf_summary_table->add_one_time_header( [$title_bar] );
	$pdf_summary_table->add_paginate_header( [$continue_bar] );
	$pdf_summary_table->add_paginate_footer( [$footer_bar] );     ##WR 695

	# WR 558
	my $vendor = $set->get( xpath => 'Payer/Vendor', must_exist => 0, value => 1 ) // '';

	if ( $vendor eq 'VEND' ) {
		$pdf_summary_table->add_every_time_header(
			format_id => 'every_time_header',
			data =>
				[ 'INVOICE DATE', 'CLAIM NUMBER/INVOICE NUMBER', 'INVOICE AMOUNT', 'DEDUCTIONS', 'INVOICE NET AMOUNT' ],
		);
	}
	elsif ( $vendor eq 'NONVEND' ) {
		$pdf_summary_table->add_every_time_header(
			format_id => 'every_time_header',
			data      => [ 'DATE OF LOSS', 'CLAIM NUMBER', 'PAID AMOUNT', 'DEDUCTIONS', 'NET PAID AMOUNT' ],
		);
	}
	else {
		$pdf_summary_table->add_every_time_header(
			format_id => 'every_time_header',
			data => [ 'INVOICE DATE', 'INVOICE NUMBER', 'INVOICE AMOUNT', 'DISCOUNT AMOUNT', 'INVOICE NET AMOUNT' ],
		);
	}

	# Table data rows preparation
	# for currency formatting
	my $format = Number::Format->new(
		decimal_fill    => '1',
		int_curr_symbol => '',
	);

	my $remit_table =
		$set->get( xpath => 'Remittance_Advice/Remittance_Table/Remittance_Row', value => 0, must_exist => 0 );
	for my $remit_node (@$remit_table) {    ## start looping through all the remittance rows

		my @data;
		my $date;
		my $formatteddate;
		my $refnum;
		my $docamt;
		my $discamt;
		my $netamt;
		my $invdet = '';

		# Prep cells data for the row
		# cell 1
		for my $node ('Ref_Date') {
			if ( $remit_node->findvalue($node) eq '' ) {
				$formatteddate = '';
			}
			else {
				$date = $remit_node->findvalue($node);
				my ( $yyyy, $mm, $dd ) = ( $date =~ /(\d+)-(\d+)-(\d+)/ );
				$formatteddate = $mm . "/" . $dd . "/" . $yyyy;
			}
		}

		# cell 2
		for my $node ('Ref_Number') {
			$refnum = $remit_node->findvalue($node);
		}

		# cell 3
		for my $node ('Doc_Amount') {

			if ( $remit_node->findvalue($node) eq '' ) {
				$docamt = '';
			}
			else {
				$docamt = $remit_node->findvalue($node);
				$docamt = $format->format_number($docamt);
				$docamt = "\$" . $docamt;

				for my $node ('Invoice_Type') {
					if ( $remit_node->findvalue($node) eq '' ) {
					}
					else {
						my $invtype = $remit_node->findvalue($node);
						if ( $invtype eq "CREN" ) {
							$docamt = $docamt . "-";
						}
					}
				}
			}
		}

		# cell 4
		for my $node ('Disc_Amount') {
			if ( $remit_node->findvalue($node) eq '' ) {
				$discamt = '$0.00';
			}
			else {
				$discamt = $remit_node->findvalue($node);
				$discamt = $format->format_number($discamt);
				$discamt = "\$" . $discamt;

				for my $node ('Invoice_Type') {
					if ( $remit_node->findvalue($node) eq '' ) {
					}
					else {
						my $invtype = $remit_node->findvalue($node);
						if ( $invtype eq "CINV" ) {
							$discamt = $discamt . "-";
						}
					}
				}
			}
		}

		# cell 5
		for my $node ('Net_Amount') {

			if ( $remit_node->findvalue($node) eq '' ) {
				$netamt = '';
			}
			else {
				$netamt = $remit_node->findvalue($node);
				$netamt = $format->format_number($netamt);
				$netamt = "\$" . $netamt;

				for my $node ('Invoice_Type') {
					if ( $remit_node->findvalue($node) eq '' ) {
					}
					else {
						my $invtype = $remit_node->findvalue($node);
						if ( $invtype eq "CREN" ) {
							$netamt = $netamt . "-";
						}
					}
				}
			}
		}

		# Invoice detail node check
		$invdet = $remit_node->findvalue('Invoice_Details');
		if ( not defined($invdet) or ( $invdet eq '' ) ) {
			$invdet = '';
		}

		# prep row data
		if (    ( $formatteddate eq '' )
			and ( $refnum eq '' )
			and ( $docamt eq '' )
			and ( $discamt eq '' )
			and ( $netamt eq '' )
			and ( $invdet eq '' ) )
		{
			next;
		}
		else {
			if (
				not(    ( $formatteddate eq '' )
					and ( $refnum eq '' )
					and ( $docamt eq '' )
					and ( $discamt eq '' || $discamt eq '$0.00' )
					and ( $netamt eq '' ) )
				)
			{
				push @data, [ $formatteddate, $refnum, $docamt, $discamt, $netamt, ];

				# add row to table
				$pdf_summary_table->add_record(
					format_id => 'record',
					data      => @data,
				);

				# cleanup array for the next row data
				@data = ();
			}
		}

		# if we have inv det node data
		for my $node ('Invoice_Details') {
			if ( $remit_node->findvalue($node) eq '' ) {
			}
			else {
				$invdet = $remit_node->findvalue($node);
				$invdet =~ s'(NOTE|DESC)//'';
				my @lines = Markup::Common::wrap2list( $invdet, 'arialmt+10', 18 );

				foreach my $lines (@lines) {
					push @data, [ $lines, undef, undef, undef, undef, ];

					$pdf_summary_table->add_record(
						format_id => 'record',
						data      => @data,
					);

					# cleanup array for the next row data
					@data = ();

				}
			}
		}
	} ## end looping

	# every_time_footer - just a top border line
	$pdf_summary_table->add_every_time_footer(
		format_id => 'every_time_footer',
		data      => [ ' ', ' ', ' ', ' ', ' ' ],
	);

	return;
}

sub _render_table {
	my ( $this, $my_table, $width, $height, $debug ) = @_;
	my $offset  = 0;
	my $leading = 0.5;
	my $results;
	my $emitted;

	if ( get_cur_sheet_num_in_set() > 1 ) {
		set_codeline 13.7, 27.5;
	}

	$results = $my_table->emit_table(
		x_pos                       => 0,
		y_pos                       => 0,
		y_length                    => $height,
		debug                       => $debug,
		die_on_table_cant_fit_issue => 1,
	);

	if ( $results->{records_not_emitted_yet} ) {
		$emitted = 0;
	}
	else { $emitted = 1; }

	return $emitted;
}

sub get_segment_info {
	my ($this) = @_;

	return {
		name        => 'BMO_ISO_Remit_Table',
		description => 'BMO ISO Remit Table complex segment',
	};
}

1;
