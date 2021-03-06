package Genome::VariantReporting::Framework::Command::Wrappers::SomaticOnly;

use strict;
use warnings;

use Genome;

use File::Basename qw(dirname);
use File::Spec;

class Genome::VariantReporting::Framework::Command::Wrappers::SomaticOnly {
    is => 'Command::V2',
    has_input => {
        model => {
            is => 'Genome::Model::SomaticValidation',
        },
        output_directory => {
            is => 'Path',
            is_output => 1,
        },
        snvs_input_vcf => {
            is => 'Path',
            is_optional => 1,
        },
        indels_input_vcf => {
            is => 'Path',
            is_optional => 1,
        },
    },
};

sub execute {
    my $self = shift;

    my $model = $self->model;
    
    my $model_pair = Genome::VariantReporting::Framework::Command::Wrappers::ModelPair->create(
        discovery => $model->last_succeeded_build,
        base_output_dir => $self->output_directory,
        plan_file_basename => 'somatic_TYPE_report.yaml',
    );
    for my $variant_type(qw(snvs indels)) {
        my $optional_vcf_method = $variant_type .'_input_vcf';
        my $input_vcf;
        if ($self->$optional_vcf_method) {
            $input_vcf = $self->$optional_vcf_method;
        } else {
            $input_vcf = $model_pair->input_vcf($variant_type)
        }
        my %params = (
            input_vcf => $input_vcf,
            variant_type => $variant_type,
            output_directory => $model_pair->reports_directory($variant_type),
            plan_file => $model_pair->plan_file($variant_type),
            resource_file => $model_pair->resource_file,
            log_directory => $model_pair->logs_directory($variant_type),
        );
        Genome::VariantReporting::Framework::Command::CreateReport->execute(%params);
    }
    return 1;
};

sub is_valid {
    my $self = shift;

    if (my @problems = $self->__errors__) {
        $self->error_message('SomaticOnly is invalid!');
        for my $problem (@problems) {
            my @properties = $problem->properties;
            $self->error_message("Property " .
                join(',', map { "'$_'" } @properties) .
                ': ' . $problem->desc);
        }
        return;
    }

    return 1;
}

1;

