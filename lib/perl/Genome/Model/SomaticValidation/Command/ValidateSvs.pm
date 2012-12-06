package Genome::Model::SomaticValidation::Command::ValidateSvs;

use strict;
use warnings;

use Genome;

class Genome::Model::SomaticValidation::Command::ValidateSvs {
    is => 'Command::V2',
    has_input => [
        build_id => {
            is => 'Text',
            doc => 'ID of the somatic validation build upon which to run',
        },
    ],
    has => [
        build => {
            is => 'Genome::Model::Build::SomaticValidation',
            id_by => 'build_id',
        },
        output_dir => {
            is_output => 1,
            is => 'Text',
            doc => 'Place where the output goes',
            is_calculated => 1,
            calculate_from => 'build',
            calculate => q{ return join("/", $build->data_directory, "sv"); }
        },
    ],


    has_optional_transient => [
        sv_call_file => {
            is => 'Text',
            is_many => 1,
            doc => 'The existing SV calls to validate',
        },
        somatic_variation_build => {
            is => 'Genome::Model::Build::SomaticVariation',
            doc => 'Original data now undergoing validation',
        },
    ],
};

sub sub_command_category { 'pipeline steps' }

sub execute {
    my $self = shift;
    my $build = $self->build;

    unless($build) {
        die $self->error_message('No build found.');
    }

    my $sv_file = $self->_resolve_svs_input();
    unless( $sv_file ) {
        #This is okay for "discovery" and "extension" validation runs.
        $self->status_message('Skipping SV validation due to lack of inputs.');
        return 1;
    }

    #gather up the pieces we need
    my $patient_id = $build->tumor_sample->name;
    my $ref_seq_build = $build->reference_sequence_build;
    my $reference_fasta = $ref_seq_build->full_consensus_path('fa');
    my $tumor_val_bam = $build->tumor_bam;
    my $normal_val_bam = $build->normal_bam;

    Genome::Sys->create_directory($self->output_dir);

    my ($merged_output_file, $merged_fasta_file) = $self->_generate_merged_callset();

    unless($ref_seq_build->subject->name eq 'human' and $ref_seq_build->version eq '36' or $ref_seq_build->version eq '37') {
        #FIXME This is horrible--why not pass the FASTA or something?
        die $self->error_message("The 'RemapReads' tool is hardcoded to only support human build 36/37");
    }

    my $readcount_output = "$merged_output_file.readcounts";
    my $validation_remap_cmd = Genome::Model::Tools::Sv::AssemblyPipeline::RemapReads->create(
        assembly_file => $merged_fasta_file,
        sv_file => $merged_output_file,
        tumor_bam => $tumor_val_bam,
        normal_bam => $normal_val_bam,
        patient_id => "VAL.$patient_id",
        output_file => $readcount_output,
        build => $ref_seq_build->version,
    );
    unless($validation_remap_cmd->execute) {
        die $self->error_message('Failed to run remap-reads on validation data');
    }

    my $classify_cmd = Genome::Model::Tools::Sv::AssemblyPipeline::ClassifyEvents->create(
        readcount_file => $readcount_output
    );
    unless($classify_cmd->execute) {
        die $self->error_message('Failed to classify events');
    }

    if($self->somatic_variation_build) {
        my $variation_build = $self->somatic_variation_build;
        my $tumor_wgs_bam = $variation_build->tumor_bam;
        my $normal_wgs_bam = $variation_build->normal_bam;

        my $wgs_remap_cmd = Genome::Model::Tools::Sv::AssemblyPipeline::RemapReads->create(
            assembly_file => $merged_fasta_file,
            sv_file => "$readcount_output.somatic", #from classify command
            tumor_bam => $tumor_wgs_bam,
            normal_bam => $normal_wgs_bam,
            patient_id => "WGS.$patient_id",
            output_file => "$readcount_output.somatic.wgs_readcounts",
            build => $ref_seq_build->version,
        );
        unless($wgs_remap_cmd->execute) {
            die $self->error_message('Failed to run remap-reads on wgs data');
        }

        $self->_process_wgs_readcounts($wgs_remap_cmd->output_file, $wgs_remap_cmd->patient_id);
    }

    my $output_dir = $self->output_dir;
    my $sv_review_command = Genome::Model::Tools::Validation::SvManualReviewContigs->create(
        contigs_output_file => "$output_dir/contigs",
        manual_review_output_file => "$output_dir/manual_review",
        merged_assembly_fasta_file => $merged_fasta_file,
        merged_sv_calls_file => $merged_output_file,
        sample_identifier => $build->tumor_sample->name,
        somatic_validation_build_id => $build->id,
        reference_sequence_build_id => $ref_seq_build->id,
    );
    unless ($sv_review_command->execute){ die "Failed to execute SV review: $@";}
    for my $model_id ($sv_review_command->realignment_model_ids){
        my $model = Genome::Model->get($model_id);
        $model->build_requested(1, "launching model created for manual review by SvManualReviewContigs");
    }

    $self->status_message('Builds have been queued for the realignment models: ' . join(" ", $sv_review_command->realignment_model_ids));

    return 1;
}


sub _resolve_svs_input {
    my $self = shift;
    my $build = $self->build;

    if(my $sv_list = $build->sv_variant_list) {
        $self->somatic_variation_build(Genome::Model::Build->get($sv_list->source_build_id));
        my $sv_file = join("/", $sv_list->output_dir, "svs.hq");
        if(-s $sv_file) {
            $self->sv_call_file([$sv_file]);
        }
    }

    unless($self->sv_call_file) {
        #fall back on any SVs generated by the original somatic variation build

        unless($self->somatic_variation_build) {
            #fall back on other priors to find the original somatic variation build
            TYPE: for my $type ("snv", "indel") {
                my $accessor = $type . '_variant_list';
                if(my $variant_list = $build->$accessor) {
                    my $som_var_build_id = $variant_list->source_build_id;
                    if($som_var_build_id) {
                        my $som_var_build = Genome::Model::Build->get($som_var_build_id);
                        $self->somatic_variation_build($som_var_build);
                        last TYPE if $som_var_build;
                    }
                }
            }

            unless($self->somatic_variation_build) {
                $self->status_message('No prior somatic variation build found.');
                return;
            }
        }

        #FIXME: clean this up so it doesn't work by happenstance
        my $sv_detection_strategy = $self->somatic_variation_build->sv_detection_strategy;
        $self->status_message("SV Detection Strategy: $sv_detection_strategy");
        $sv_detection_strategy =~ /(breakdancer.*?])/;
        my $breakdancer = $1;
        $self->status_message("Breakdancer: $breakdancer");
        $sv_detection_strategy =~ /filtered by.*? (novo-realign .*)then/;
        my $filter = $1;
        $self->status_message("Filter: $filter");
        my $sv_file = join('/', $self->somatic_variation_build->path_to_individual_output($breakdancer, $filter), 'svs.hq');
        $self->status_message("Using somatic variation build: " . $self->somatic_variation_build->id);
        $self->status_message("Looking for $sv_file");

        if(-s $sv_file) {
            $self->sv_call_file([$sv_file]);
        } else {
            $self->status_message('No prior SV calls found in somatic variation build ' . $self->somatic_variation_build->__display_name__);
            return;
        }
    }

    return 1;
}

sub _generate_merged_callset {
    my $self = shift;
    my $build = $self->build;

    my $assembly_input_file = join("/", $self->output_dir, "assembly_input");
    Genome::Sys->create_symlink($self->sv_call_file, $assembly_input_file);
    my $assembly_output_file = join("/", $self->output_dir, "assembly_output.csv");
    my $assembly_output_fasta = join("/", $self->output_dir, "assembly_output.fasta");
    my $assembly_output_cm = join("/", $self->output_dir, "assembly_output.cm");

    my $tumor_val_bam = $build->tumor_bam;
    my $normal_val_bam = $build->normal_bam;
    my $ref_seq_build = $build->reference_sequence_build;
    my $reference_fasta = $ref_seq_build->full_consensus_path('fa');

    my $assembly_cmd = Genome::Model::Tools::Sv::AssemblyValidation->create(
        bam_files => join(",", $tumor_val_bam, $normal_val_bam),
        output_file => $assembly_output_file,
        sv_file => $assembly_input_file,
        asm_high_coverage => 1,
        min_size_of_confirm_asm_sv => 10,
        breakpoint_seq_file => $assembly_output_fasta,
        cm_aln_file => $assembly_output_cm,
        reference_file => $reference_fasta,
    );
    unless($assembly_cmd->execute) {
        die $self->error_message('Failed to execute assembly-validation command.');
    }

    #merge assembled callsets requires an "index" of the files to use
    my $index_file = $assembly_output_file . '.index';
    Genome::Sys->write_file($index_file, join("\t", "calls", $assembly_output_file, $assembly_output_fasta));

    my $merged_output_file = "$assembly_output_file.merged";
    my $merged_fasta_file = "$assembly_output_fasta.merged";
    my $merge_cmd = Genome::Model::Tools::Sv::MergeAssembledCallsets->create(
        index_file => $index_file,
        output_file => $merged_output_file,
        output_fasta => $merged_fasta_file,
    );
    unless($merge_cmd->execute) {
        die $self->error_message('Failed to merge callsets');
    }

    return ($merged_output_file, $merged_fasta_file);
}

sub _process_wgs_readcounts {
    my $self = shift;
    my $wgs_readcounts_file = shift;
    my $wgs_patient_id = shift;

    my $normal_wgs_reads_cutoff = 0; #Possibly a future PP param?

    my $somatic_file = "$wgs_readcounts_file.somatic";
    my $somatic_fh = Genome::Sys->open_file_for_writing($somatic_file);

    my $readcount_fh = Genome::Sys->open_file_for_reading($wgs_readcounts_file);

    while (my $line = $readcount_fh->getline) {
        if ( $line =~ /^#/ ) { print $somatic_fh $line; next; }
        if ( $line =~ /no\s+fasta\s+sequence/ ) { next; }
        if ( $line =~ /$wgs_patient_id.normal.svReadCount\:(\d+)/i ) {
            my ($normal_sv_readcount) = $line =~ /$wgs_patient_id.normal.svReadCount\:(\d+)/i;
            if ($normal_sv_readcount > $normal_wgs_reads_cutoff) { next; }
            else { print $somatic_fh $line; next; }
        }
    }
    $readcount_fh->close;
    $somatic_fh->close;

    return $somatic_file;
}


1;
